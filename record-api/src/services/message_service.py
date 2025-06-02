import redis
import json

class MessageService:
    def __init__(self, redis_client, message_model):
        self.redis_client = redis_client
        self.message_model = message_model

    def store_message_in_history(self, user_id_send, user_id_receive, message):
        try:
            success = self.message_model.create(user_id_send, user_id_receive, message)
            if success:
                return {'status': 'Message recorded in history'}
            else:
                return {'error': 'Failed to record message in history due to database error', 'status_code': 500}
        except Exception as e:
            return {'error': f'Failed to record message in history: {str(e)}', 'status_code': 500}

    def get_messages_for_user(self, user_id_receive):
        cache_key = f'messages_received:{user_id_receive}'
        try:
            cached_messages_json_list = self.redis_client.lrange(cache_key, 0, -1)
            if cached_messages_json_list:
                return [json.loads(msg_json.decode('utf-8')) for msg_json in cached_messages_json_list]

            db_messages_tuples = self.message_model.find_by_user_receive(user_id_receive)
            if db_messages_tuples is None:
                 return {'error': 'Failed to retrieve messages from database', 'status_code': 500}

            messages_list = []
            if db_messages_tuples:
                pipe = self.redis_client.pipeline()
                for row_tuple in db_messages_tuples:
                    msg_dict = {
                        'id': row_tuple[0],
                        'userIdSend': row_tuple[1],
                        'userIdReceive': row_tuple[2],
                        'message': row_tuple[3],
                        'created_at': row_tuple[4].isoformat() if row_tuple[4] else None
                    }
                    messages_list.append(msg_dict)
                    pipe.rpush(cache_key, json.dumps(msg_dict))
                pipe.expire(cache_key, 3600)
                pipe.execute()
            return messages_list
        except redis.RedisError as e:
            return {'error': f'Redis error in get_messages_for_user: {str(e)}', 'status_code': 500}
        except Exception as e:
            return {'error': f'Server error in get_messages_for_user: {str(e)}', 'status_code': 500}

    def get_messages_for_channel(self, user_id_send, user_id_receive):
        
        key_part1 = min(str(user_id_send), str(user_id_receive))
        key_part2 = max(str(user_id_send), str(user_id_receive))
        cache_key = f'messages_channel:{key_part1}_{key_part2}'
        
        try:
            cached_messages_json_list = self.redis_client.lrange(cache_key, 0, -1)
            if cached_messages_json_list:
                return [json.loads(msg_json.decode('utf-8')) for msg_json in cached_messages_json_list]

            db_messages_tuples = self.message_model.find_by_channel(user_id_send, user_id_receive)
            if db_messages_tuples is None:
                return {'error': 'Failed to retrieve channel messages from database', 'status_code': 500}
            
            messages_list = []
            if db_messages_tuples:
                pipe = self.redis_client.pipeline()
                for row_tuple in db_messages_tuples:
                    msg_dict = {
                        'id': row_tuple[0],
                        'userIdSend': row_tuple[1],
                        'userIdReceive': row_tuple[2],
                        'message': row_tuple[3],
                        'created_at': row_tuple[4].isoformat() if row_tuple[4] else None
                    }
                    messages_list.append(msg_dict)
                    pipe.rpush(cache_key, json.dumps(msg_dict))
                pipe.expire(cache_key, 3600)
                pipe.execute()
            return messages_list
        except redis.RedisError as e:
            return {'error': f'Redis error in get_messages_for_channel: {str(e)}', 'status_code': 500}
        except Exception as e:
            return {'error': f'Server error in get_messages_for_channel: {str(e)}', 'status_code': 500}