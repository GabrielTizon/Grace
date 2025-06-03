<?php
require '/app/vendor/autoload.php';

use Firebase\JWT\JWT;
use Firebase\JWT\Key;

// ✅ Carregar .env da raiz do projeto
$dotenvPath = dirname(__DIR__) . '/.env';
if (file_exists($dotenvPath)) {
    Dotenv\Dotenv::createImmutable(dirname(__DIR__))->load();
}

header('Content-Type: application/json');

// ✅ Configuração via variáveis de ambiente (.env na raiz)
$host = getenv('DB_HOST') ?: 'db';
$dbname = getenv('DB_NAME') ?: 'messagedb';
$dbUser = getenv('DB_USER') ?: 'user';
$dbPassword = getenv('DB_PASS') ?: 'password';
$jwtSecret = getenv('JWT_SECRET') ?: 'shawarma';

$dsn = "pgsql:host=$host;port=5432;dbname=$dbname";

try {
    $pdo = new PDO($dsn, $dbUser, $dbPassword);
    $pdo->setAttribute(PDO::ATTR_ERRMODE, PDO::ERRMODE_EXCEPTION);
} catch (PDOException $e) {
    http_response_code(500);
    echo json_encode(['error' => 'Database connection failed: ' . $e->getMessage()]);
    exit;
}

require_once __DIR__ . '/../Models/UserModel.php';
$userModel = new \Models\UserModel($pdo);

$input = json_decode(file_get_contents('php://input'), true);
$uri = parse_url($_SERVER['REQUEST_URI'], PHP_URL_PATH);
$method = $_SERVER['REQUEST_METHOD'] ?? 'GET';

function json_response($data, $statusCode = 200) {
    http_response_code($statusCode);
    echo json_encode($data);
    exit;
}

// Health Check
if ($method === 'GET' && $uri === '/health') {
    json_response(['status' => 'OK']);
}

// Login
if ($method === 'POST' && $uri === '/token') {
    if (!isset($input['email'], $input['password'])) {
        json_response(['error' => 'Email and password required'], 400);
    }

    $email = $input['email'];
    $password = $input['password'];
    $user = $userModel->findByEmail($email);

    if ($user && password_verify($password, $user['password'])) {
        $payload = [
            'iss' => "auth-api",
            'aud' => "microservices-chat",
            'iat' => time(),
            'exp' => time() + 3600,
            'userId' => $user['id'],
            'email' => $user['email'],
        ];
        $jwt = JWT::encode($payload, $jwtSecret, 'HS256');
        json_response(['token' => $jwt]);
    } else {
        json_response(['error' => 'Invalid credentials'], 401);
    }
}

// Verifica token de autenticação
if ($method === 'GET' && $uri === '/token') {
    $userIdentifier = $_GET['userIdentifier'] ?? null;
    $authHeader = $_SERVER['HTTP_AUTHORIZATION'] ?? null;

    if (!$userIdentifier || !$authHeader || !preg_match('/Bearer\s(\S+)/', $authHeader, $matches)) {
        json_response(['auth' => false, 'error' => 'User identifier and token are required'], 401);
    }

    try {
        $decoded = JWT::decode($matches[1], new Key($jwtSecret, 'HS256'));
        $user = $userModel->findByEmail($userIdentifier);
        if ($user && $user['id'] == $decoded->userId) {
            json_response(['auth' => true]);
        } else {
            json_response(['auth' => false, 'error' => 'Token mismatch or user not found'], 401);
        }
    } catch (Exception $e) {
        json_response(['auth' => false, 'error' => 'Invalid token: ' . $e->getMessage()], 401);
    }
}

// Cadastro de usuário
if ($method === 'POST' && $uri === '/user') {
    if (!isset($input['password'], $input['name'], $input['lastName'], $input['email'])) {
        json_response(['error' => 'Password, name, lastName, and email required'], 400);
    }

    $hashedPassword = password_hash($input['password'], PASSWORD_BCRYPT);

    try {
        $userId = $userModel->create($hashedPassword, $input['name'], $input['lastName'], $input['email']);
        $user = $userModel->findById($userId);
        unset($user['password']);
        json_response(['message' => 'ok', 'user' => $user], 201);
    } catch (PDOException $e) {
        if (strpos($e->getMessage(), 'duplicate') !== false) {
            json_response(['error' => 'Email already exists'], 400);
        }
        json_response(['error' => 'Database error: ' . $e->getMessage()], 500);
    }
}

// Listar usuários
if ($method === 'GET' && $uri === '/user') {
    if (isset($_GET['all']) && $_GET['all'] === 'true') {
        $users = $userModel->getAllUsers();
        json_response($users);
    }

    if (!isset($_GET['email'])) {
        json_response(['error' => 'Email query parameter is required'], 400);
    }

    $user = $userModel->findByEmail($_GET['email']);
    if ($user) {
        unset($user['password']);
        json_response($user);
    } else {
        json_response(['error' => 'User not found'], 404);
    }
}

json_response(['error' => 'Endpoint not found'], 404);
