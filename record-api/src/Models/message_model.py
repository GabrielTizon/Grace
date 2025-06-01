class MessageModel:
    def __init__(self, db):
        self.db = db

    def create(self, user, message):
        with self.db.cursor() as cur:
            cur.execute("INSERT INTO messages (user, message) VALUES (%s, %s)", (user, message))
            self.db.commit()

    def find_by_user(self, user):
        with self.db.cursor() as cur:
            cur.execute("SELECT message FROM messages WHERE user = %s", (user,))
            return [row[0] for row in cur.fetchall()]