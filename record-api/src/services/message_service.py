class MessageService:
    def __init__(self, redis_client, message_model):
        self.redis_client = redis_client
        self.message_model = message_model

    def store_message(self, user, message):
        cache_key = f'messages:{user}'
        # Store in Redis (cache)
        self.redis_client.lpush(cache_key, message)
        self.redis_client.expire(cache_key, 3600)  # Cache for 1 hour
        # Persist in database
        try:
            self.message_model.create(user, message)
            return {'message': 'Message stored'}
        except Exception as e:
            return {'error': f'Failed to store message: {str(e)}'}

    def get_messages(self, user):
        cache_key = f'messages:{user}'
        # Check cache
        messages = self.redis_client.lrange(cache_key, 0, -1)
        if messages:
            return messages
        # Fallback to database
        try:
            messages = self.message_model.find_by_user(user)
            if messages:
                # Cache results
                for msg in messages:
                    self.redis_client.lpush(cache_key, msg)
                self.redis_client.expire(cache_key, 3600)
            return messages
        except Exception as e:
            return {'error': f'Failed to retrieve messages: {str(e)}'}