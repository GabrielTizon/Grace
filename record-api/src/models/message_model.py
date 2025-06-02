class MessageModel:
    def __init__(self, db_connection):
        self.db = db_connection

    def create(self, user_id_send, user_id_receive, message):
        try:
            with self.db.cursor() as cur:
                cur.execute(
                    "INSERT INTO messages (userIdSend, userIdReceive, message) VALUES (%s, %s, %s)",
                    (user_id_send, user_id_receive, message)
                )
                self.db.commit()
            return True
        except Exception as e:
            self.db.rollback()
            print(f"Error in MessageModel.create: {e}")
            return False

    def find_by_user_receive(self, user_id_receive):
        try:
            with self.db.cursor() as cur:
                cur.execute("SELECT id, userIdSend, userIdReceive, message, created_at FROM messages WHERE userIdReceive = %s ORDER BY created_at DESC", (user_id_receive,))
                return cur.fetchall()
        except Exception as e:
            print(f"Error in MessageModel.find_by_user_receive: {e}")
            return []

    def find_by_channel(self, user_id_send, user_id_receive):
        try:
            with self.db.cursor() as cur:
                sql = """
                    SELECT id, userIdSend, userIdReceive, message, created_at 
                    FROM messages 
                    WHERE (userIdSend = %s AND userIdReceive = %s) OR (userIdSend = %s AND userIdReceive = %s)
                    ORDER BY created_at ASC
                """
                cur.execute(sql, (user_id_send, user_id_receive, user_id_receive, user_id_send))
                return cur.fetchall()
        except Exception as e:
            print(f"Error in MessageModel.find_by_channel: {e}")
            return []