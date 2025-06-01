from flask import Flask, jsonify
import redis
import os

app = Flask(__name__)

# Conexão com Redis
redis_client = redis.Redis(host=os.getenv('REDIS_HOST', 'redis'), port=6379, decode_responses=True)

@app.route('/')
def index():
    return jsonify({'status': 'ok'})

@app.route('/messages', methods=['GET'])
def get_messages():
    try:
        messages = redis_client.lrange('messages', 0, -1)
        return jsonify({'messages': messages})
    except Exception as e:
        return jsonify({'error': str(e)}), 500

@app.route('/messages/<username>', methods=['GET'])
def get_user_messages(username):
    try:
        # Placeholder: Fetch user-specific messages if implemented
        return jsonify({'error': 'User-specific messages not implemented'}), 501
    except Exception as e:
        return jsonify({'error': str(e)}), 500

if __name__ == '__main__':
    app.run(host='0.0.0.0', port=5000)