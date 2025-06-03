# record-api/src/services/message_service.py
import json, redis
from datetime import datetime


class MessageService:
    def __init__(self, redis_client, message_model):
        self.redis = redis_client
        self.model = message_model

    # ---------- helper ----------
    @staticmethod
    def _to_serializable(row: dict) -> dict:
        """Converte datetime → isoformat para JSON."""
        row = row.copy()
        if isinstance(row.get("created_at"), datetime):
            row["created_at"] = row["created_at"].isoformat()
        return row

    def _deserialize(self, raw):
        if isinstance(raw, (bytes, bytearray)):
            raw = raw.decode("utf-8")
        return json.loads(raw)

    # ---------- criar ----------
    def store_message_in_history(self, user_id_send, user_id_receive, message):
        row = self.model.create(user_id_send, user_id_receive, message)
        if row is None:
            return None

        # invalida caches
        self.redis.delete(f"messages_received:{user_id_receive}")
        min_id, max_id = sorted((user_id_send, user_id_receive))
        self.redis.delete(f"messages_channel:{min_id}_{max_id}")

        return row

    # ---------- inbox ----------
    def get_messages_for_user(self, user_id_receive):
        key = f"messages_received:{user_id_receive}"

        try:
            cached = self.redis.lrange(key, 0, -1)
            if cached:
                return [self._deserialize(c) for c in cached]

            rows = self.model.find_by_user_receive(user_id_receive)
            if rows is None:
                return None

            pipe = self.redis.pipeline()
            for r in rows:
                serial = self._to_serializable(r)
                pipe.rpush(key, json.dumps(serial))
            pipe.expire(key, 3600).execute()
            return rows
        except redis.RedisError as e:
            print(f"[Redis] {e}")
            return rows if "rows" in locals() else None

    # ---------- canal ----------
    def get_messages_for_channel(self, u1, u2):
        min_id, max_id = sorted((u1, u2))
        key = f"messages_channel:{min_id}_{max_id}"

        try:
            cached = self.redis.lrange(key, 0, -1)
            if cached:
                return [self._deserialize(c) for c in cached]

            rows = self.model.find_by_channel(u1, u2)
            if rows is None:
                return None

            pipe = self.redis.pipeline()
            for r in rows:
                serial = self._to_serializable(r)
                pipe.rpush(key, json.dumps(serial))
            pipe.expire(key, 3600).execute()
            return rows
        except redis.RedisError as e:
            print(f"[Redis] {e}")
            return rows if "rows" in locals() else None
