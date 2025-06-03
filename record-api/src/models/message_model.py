from psycopg2.extras import RealDictCursor

class MessageModel:
    def __init__(self, db_conn):
        self.db = db_conn

    def create(self, user_id_send, user_id_receive, message):
        sql = """
            INSERT INTO messages ("userIdSend", "userIdReceive", message)
            VALUES (%s, %s, %s)
            RETURNING id, created_at;
        """
        try:
            with self.db.cursor(cursor_factory=RealDictCursor) as cur:
                cur.execute(sql, (user_id_send, user_id_receive, message))
                row = cur.fetchone()
            self.db.commit()
            return {'id': row['id'], 'created_at': row['created_at'].isoformat()}
        except Exception as e:
            self.db.rollback()
            print(f"[MessageModel.create] {e}")
            return None

    def find_by_user_receive(self, user_id_receive):
        sql = """
            SELECT id, user_id_send, user_id_receive, message, created_at
            FROM messages
            WHERE user_id_receive = %s
            ORDER BY created_at DESC;
        """
        try:
            with self.db.cursor(cursor_factory=RealDictCursor) as cur:
                cur.execute(sql, (user_id_receive,))
                return cur.fetchall()
        except Exception as e:
            print(f"[MessageModel.find_by_user_receive] {e}")
            return None

    def find_by_channel(self, user_id1, user_id2):
        sql = """
            SELECT id, user_id_send, user_id_receive, message, created_at
            FROM messages
            WHERE (user_id_send=%s AND user_id_receive=%s)
               OR (user_id_send=%s AND user_id_receive=%s)
            ORDER BY created_at ASC;
        """
        try:
            with self.db.cursor(cursor_factory=RealDictCursor) as cur:
                cur.execute(sql, (user_id1, user_id2, user_id2, user_id1))
                return cur.fetchall()
        except Exception as e:
            print(f"[MessageModel.find_by_channel] {e}")
            return None
