from flask import Flask, jsonify, request
import redis
import os
import psycopg2
import json

from models.message_model import MessageModel
from services.message_service import MessageService

app = Flask(__name__)

try:
    db_connection = psycopg2.connect(
        dbname=os.getenv('DB_NAME', 'mydb'),
        user=os.getenv('DB_USER', 'user'),
        password=os.getenv('DB_PASS', 'password'),
        host=os.getenv('DB_HOST', 'db'),
        port=os.getenv('DB_PORT', '5432')
    )
except psycopg2.OperationalError as e:
    print(f"FATAL: Could not connect to PostgreSQL database: {e}")
    raise

try:
    redis_client = redis.Redis(
        host=os.getenv('REDIS_HOST', 'redis'),
        port=6379,
        decode_responses=False, 
        retry_on_timeout=True
    )
    redis_client.ping()
    print("Successfully connected to Redis.")
except redis.exceptions.ConnectionError as e:
    print(f"FATAL: Could not connect to Redis: {e}")
    raise

message_model = MessageModel(db_connection)
message_service = MessageService(redis_client, message_model)

@app.route('/')
def index():
    redis_ping_success = False
    try:
        redis_ping_success = redis_client.ping()
    except:
        pass
    return jsonify({'status': 'Record-API is running', 'redis_ping': redis_ping_success})

@app.route('/message', methods=['POST'])
def record_message_to_history_route():
    data = request.get_json()
    if not data or 'message' not in data or 'userIdSend' not in data or 'userIdReceive' not in data:
        return jsonify({'error': 'Missing message, userIdSend, or userIdReceive in payload'}), 400

    message_content = data['message']
    user_id_send = data['userIdSend']
    user_id_receive = data['userIdReceive']

    result = message_service.store_message_in_history(user_id_send, user_id_receive, message_content)
    
    status_code = result.get('status_code', 500) if 'error' in result else 201
    if 'error' in result:
         return jsonify(result), status_code
    return jsonify({'ok': True, 'detail': result.get('status', 'Message recorded')}), status_code

@app.route('/messages_for_user/<user_id_receive>', methods=['GET'])
def get_messages_for_user_route(user_id_receive):
    messages = message_service.get_messages_for_user(user_id_receive)
    status_code = messages.get('status_code', 500) if isinstance(messages, dict) and 'error' in messages else 200
    if isinstance(messages, dict) and 'error' in messages:
        return jsonify(messages), status_code
    return jsonify({'messages': messages}), status_code

@app.route('/messages_for_channel/<user_id1>/<user_id2>', methods=['GET'])
def get_messages_for_channel_route(user_id1, user_id2):
    messages = message_service.get_messages_for_channel(user_id1, user_id2)
    status_code = messages.get('status_code', 500) if isinstance(messages, dict) and 'error' in messages else 200
    if isinstance(messages, dict) and 'error' in messages:
        return jsonify(messages), status_code
    return jsonify({'messages': messages}), status_code

if __name__ == '__main__':
    app.run(host='0.0.0.0', port=5000)