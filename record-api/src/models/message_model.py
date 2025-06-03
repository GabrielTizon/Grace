# record-api/src/models/message_model.py
from psycopg2.extras import RealDictCursor


class MessageModel:
    def __init__(self, db_conn):
        self.db = db_conn

    # ------------------------------------------------------------
    # INSERT
    # ------------------------------------------------------------
    def create(self, user_id_send: int | str, user_id_receive: int | str, message: str):
        """
        Grava uma mensagem no banco. As colunas useridsend / useridreceive
        são TEXT, portanto convertemos os IDs para string antes do INSERT.
        """
        sql = """
            INSERT INTO messages (useridsend, useridreceive, message)
            VALUES (%s, %s, %s)
            RETURNING id, created_at;
        """
        try:
            with self.db.cursor(cursor_factory=RealDictCursor) as cur:
                cur.execute(sql, (str(user_id_send), str(user_id_receive), message))
                row = cur.fetchone()
            self.db.commit()
            return {
                "id": row["id"],
                "created_at": row["created_at"].isoformat()
            }
        except Exception as e:
            self.db.rollback()
            print(f"[MessageModel.create] {e}")
            return None

    # ------------------------------------------------------------
    # READ – Todas as mensagens RECEBIDAS por um usuário
    # ------------------------------------------------------------
    def find_by_user_receive(self, user_id_receive: int | str):
        sql = """
            SELECT id,
                   useridsend    AS user_id_send,
                   useridreceive AS user_id_receive,
                   message,
                   created_at
              FROM messages
             WHERE useridreceive = %s
          ORDER BY created_at DESC;
        """
        try:
            with self.db.cursor(cursor_factory=RealDictCursor) as cur:
                cur.execute(sql, (str(user_id_receive),))
                return cur.fetchall()          # [] se não houver registros
        except Exception as e:
            print(f"[MessageModel.find_by_user_receive] {e}")
            return None                       # None indica erro interno

    # ------------------------------------------------------------
    # READ – Histórico de um canal (u1  ↔  u2)
    # ------------------------------------------------------------
    def find_by_channel(self, user_id1: int | str, user_id2: int | str):
        sql = """
            SELECT id,
                   useridsend    AS user_id_send,
                   useridreceive AS user_id_receive,
                   message,
                   created_at
              FROM messages
             WHERE (useridsend = %s AND useridreceive = %s)
                OR (useridsend = %s AND useridreceive = %s)
          ORDER BY created_at ASC;
        """
        try:
            with self.db.cursor(cursor_factory=RealDictCursor) as cur:
                cur.execute(
                    sql,
                    (str(user_id1), str(user_id2), str(user_id2), str(user_id1))
                )
                return cur.fetchall()
        except Exception as e:
            print(f"[MessageModel.find_by_channel] {e}")
            return None
