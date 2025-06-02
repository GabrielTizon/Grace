import json, redis

class MessageService:
    def __init__(self, redis_client, message_model):
        self.redis = redis_client
        self.model = message_model

    # --- helpers ---
    def _deserialize(self, raw):
        """bytes → str → dict"""
        if isinstance(raw, (bytes, bytearray)):
            raw = raw.decode('utf-8')
        return json.loads(raw)

    # ------------- criar -------------
    def store_message_in_history(self, user_id_send, user_id_receive, message):
        # grava banco
        row = self.model.create(user_id_send, user_id_receive, message)
        if row is None:
            return None

        # invalida caches relacionados
        self.redis.delete(f"messages_received:{user_id_receive}")
        min_id, max_id = sorted((user_id_send, user_id_receive))
        self.redis.delete(f"messages_channel:{min_id}_{max_id}")

        return row

    # ------------- leitura por destinatário -------------
    def get_messages_for_user(self, user_id_receive):
        cache_key = f"messages_received:{user_id_receive}"

        try:
            cached = self.redis.lrange(cache_key, 0, -1)
            if cached:
                return [self._deserialize(x) for x in cached]

            rows = self.model.find_by_user_receive(user_id_receive)
            if rows is None:
                return None

            # guarda no cache
            pipe = self.redis.pipeline()
            for r in rows:
                pipe.rpush(cache_key, json.dumps(r))
            pipe.expire(cache_key, 3600).execute()
            return rows
        except redis.RedisError as e:
            print(f"[Redis] {e}")
            return rows if 'rows' in locals() else None

    # ------------- leitura por canal -------------
    def get_messages_for_channel(self, u1, u2):
        min_id, max_id = sorted((u1, u2))
        cache_key = f"messages_channel:{min_id}_{max_id}"

        try:
            cached = self.redis.lrange(cache_key, 0, -1)
            if cached:
                return [self._deserialize(x) for x in cached]

            rows = self.model.find_by_channel(u1, u2)
            if rows is None:
                return None

            pipe = self.redis.pipeline()
            for r in rows:
                pipe.rpush(cache_key, json.dumps(r))
            pipe.expire(cache_key, 3600).execute()
            return rows
        except redis.RedisError as e:
            print(f"[Redis] {e}")
            return rows if 'rows' in locals() else None
