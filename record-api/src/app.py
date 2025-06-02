from flask import Flask, jsonify
import redis
import os
from models.message_model import MessageModel
from services.message_service import MessageService
import psycopg2  # Assuming PostgreSQL for MessageModel

app = Flask(__name__)

# Database connection (adjust as per your DB setup)
db = psycopg2.connect(
    dbname=os.getenv('DB_NAME', 'your_db'),
    user=os.getenv('DB_USER', 'your_user'),
    password=os.getenv('DB_PASS', 'your_password'),
    host=os.getenv('DB_HOST', 'db'),
    port=os.getenv('DB_PORT', '5432')
)

# Redis connection
redis_client = redis.Redis(
    host=os.getenv('REDIS_HOST', 'redis'),
    port=6379,
    decode_responses=True,
    retry_on_timeout=True
)

# Initialize services
message_model = MessageModel(db)
message_service = MessageService(redis_client, message_model)

@app.route('/')
def index():
    return jsonify({'status': 'ok'})

@app.route('/messages', methods=['GET'])
def get_messages():
    try:
        messages = message_service.get_messages('global')  # Use a generic user or modify as needed
        if isinstance(messages, dict) and 'error' in messages:
            return jsonify(messages), 500
        return jsonify({'messages': messages})
    except redis.RedisError as e:
        return jsonify({'error': f'Redis error: {str(e)}'}), 500
    except Exception as e:
        return jsonify({'error': f'Server error: {str(e)}'}), 500

@app.route('/messages/<username>', methods=['GET'])
def get_user_messages(username):
    try:
        messages = message_service.get_messages(username)
        if isinstance(messages, dict) and 'error' in messages:
            return jsonify(messages), 500
        return jsonify({'messages': messages})
    except redis.RedisError as e:
        return jsonify({'error': f'Redis error: {str(e)}'}), 500
    except Exception as e:
        return jsonify({'error': f'Server error: {str(e)}'}), 500

if __name__ == '__main__':
    app.run(host='0.0.0.0', port=5000)