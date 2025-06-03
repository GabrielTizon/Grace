from flask import Flask, jsonify, request
import os
import redis
import psycopg2
from dotenv import load_dotenv, find_dotenv
from models.message_model import MessageModel
from services.message_service import MessageService

load_dotenv(find_dotenv())

app = Flask(__name__)

# ---------- Conexão PostgreSQL ----------
try:
    db_connection = psycopg2.connect(
        dbname=os.getenv('DB_NAME', 'messagedb'),
        user=os.getenv('DB_USER', 'user'),
        password=os.getenv('DB_PASS', 'password'),
        host=os.getenv('DB_HOST', 'localhost'),
        port=os.getenv('DB_PORT', '5432')
    )
except Exception as e:
    print(f"❌ Falha ao conectar ao PostgreSQL: {e}")
    raise

# ---------- Conexão Redis ----------
try:
    redis_client = redis.Redis(
        host=os.getenv('REDIS_HOST', 'localhost'),
        port=int(os.getenv('REDIS_PORT', 6379)),
        decode_responses=False,
        retry_on_timeout=True
    )
    redis_client.ping()
except Exception as e:
    print(f"❌ Falha ao conectar ao Redis: {e}")
    raise

# ---------- Instâncias de Model / Service ----------
message_model = MessageModel(db_connection)
message_service = MessageService(redis_client, message_model)

# ---------- Rotas ----------
@app.route('/')
def index():
    return jsonify({
        'status': 'Record-API rodando',
        'redis_ping': redis_client.ping()
    })

@app.route('/message', methods=['POST'])
def record_message():
    data = request.get_json(force=True)
    required = {'userIdSend', 'userIdReceive', 'message'}
    if not required.issubset(data):
        return jsonify({'error': 'Campos obrigatórios faltando'}), 400

    result = message_service.store_message_in_history(
        data['userIdSend'], data['userIdReceive'], data['message']
    )
    if result is None:
        return jsonify({'error': 'Falha ao gravar'}), 500
    return jsonify({'ok': True, **result}), 201

@app.route('/messages_for_user/<int:user_id>', methods=['GET'])
def messages_for_user(user_id):
    rows = message_service.get_messages_for_user(user_id)
    if rows is None:
        return jsonify({'error': 'Falha interna'}), 500
    return jsonify({'messages': rows}), 200

@app.route('/messages_for_channel/<int:u1>/<int:u2>', methods=['GET'])
def messages_for_channel(u1, u2):
    rows = message_service.get_messages_for_channel(u1, u2)
    if rows is None:
        return jsonify({'error': 'Falha interna'}), 500
    return jsonify({'messages': rows}), 200

if __name__ == '__main__':
    app.run(host='0.0.0.0', port=int(os.getenv('PORT', 5000)))
