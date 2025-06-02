<?php
require '/app/vendor/autoload.php';
use Firebase\JWT\JWT;
use Firebase\JWT\Key;

header('Content-Type: application/json');

$host = getenv('DB_HOST') ?: 'db';
$dbname = getenv('DB_NAME') ?: 'mydb';
$dbUser = getenv('DB_USER') ?: 'user';
$dbPassword = getenv('DB_PASS') ?: 'password';
$dsn = "pgsql:host=$host;port=5432;dbname=$dbname";
$jwtSecret = getenv('JWT_SECRET') ?: 'your_very_secure_secret_key_auth';

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
$uri = $_SERVER['REQUEST_URI'] ?? '/';
$method = $_SERVER['REQUEST_METHOD'] ?? 'GET';

function json_response($data, $statusCode = 200) {
    http_response_code($statusCode);
    echo json_encode($data);
    exit;
}

if ($method === 'GET' && $uri === '/health') {
    json_response(['status' => 'OK']);
}

if ($method === 'GET' && preg_match('#^/token#', $uri)) {
    $userIdentifier = $_GET['userIdentifier'] ?? null;
    $authHeader = $_SERVER['HTTP_AUTHORIZATION'] ?? null;

    if (!$userIdentifier || !$authHeader || !preg_match('/Bearer\s(\S+)/', $authHeader, $matches)) {
        json_response(['auth' => false, 'error' => 'User identifier and token are required'], 401);
    }
    $token = $matches[1];

    try {
        $decoded = JWT::decode($token, new Key($jwtSecret, 'HS256'));
        
        $tokenUserEmail = $decoded->email ?? null;
        $tokenUserId = $decoded->userId ?? null;

        if (!$tokenUserEmail && !$tokenUserId) {
            json_response(['auth' => false, 'error' => 'Token does not contain user identifier'], 401);
        }

        $queriedUser = $userModel->findByEmail($userIdentifier) ?: $userModel->findByUsername($userIdentifier);

        if (!$queriedUser) {
            json_response(['auth' => false, 'error' => 'Queried user not found'], 401);
        }

        $tokenMatchesQueryUser = false;
        if ($tokenUserEmail && $tokenUserEmail === $queriedUser['email']) {
            $tokenMatchesQueryUser = true;
        } elseif ($tokenUserId && $tokenUserId === $queriedUser['id']) {
            $tokenMatchesQueryUser = true;
        }
        
        if ($tokenMatchesQueryUser) {
            $userFromToken = $tokenUserEmail ? $userModel->findByEmail($tokenUserEmail) : $userModel->findById($tokenUserId);
            if ($userFromToken) {
                 json_response(['auth' => true]);
            } else {
                 json_response(['auth' => false, 'error' => 'User in token no longer exists'], 401);
            }
        } else {
            json_response(['auth' => false, 'error' => 'Token does not match the specified user'], 401);
        }
    } catch (Exception $e) {
        json_response(['auth' => false, 'error' => 'Invalid token: ' . $e->getMessage()], 401);
    }
}

if ($method === 'POST' && preg_match('#^/token#', $uri)) {
    if (!isset($input['email'], $input['password'])) {
        json_response(['error' => 'Email and password required'], 400);
    }
    $email = $input['email'];
    $password = $input['password'];

    try {
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
            json_response(['token' => false], 401);
        }
    } catch (PDOException $e) {
        json_response(['error' => 'Database error: ' . $e->getMessage()], 500);
    }
}

if ($method === 'POST' && preg_match('#^/user#', $uri)) {
    if (!isset($input['username'], $input['password'], $input['name'], $input['lastName'], $input['email'])) {
        json_response(['error' => 'Username, password, name, lastName, and email required'], 400);
    }
    $username = $input['username'];
    $hashedPassword = password_hash($input['password'], PASSWORD_BCRYPT);
    $name = $input['name'];
    $lastName = $input['lastName'];
    $email = $input['email'];

    try {
        $newUserId = $userModel->create($username, $hashedPassword, $name, $lastName, $email);
        if ($newUserId) {
            $createdUser = $userModel->findById($newUserId);
            unset($createdUser['password']);
            json_response([
                'message' => 'ok',
                'user' => [
                    'id' => $createdUser['id'],
                    'username' => $createdUser['username'],
                    'name' => $createdUser['name'],
                    'lastName' => $createdUser['lastName'],
                    'email' => $createdUser['email']
                ]
            ], 201);
        } else {
            json_response(['error' => 'Registration failed'], 400);
        }
    } catch (PDOException $e) {
        if (strpos($e->getMessage(), 'duplicate key') !== false || strpos($e->getMessage(), 'UniqueViolation') !== false) {
            json_response(['error' => 'Username or email already exists'], 400);
        } else {
            json_response(['error' => 'Database error during registration: ' . $e->getMessage()], 500);
        }
    }
}

if ($method === 'GET' && preg_match('#^/user#', $uri)) {
    $email = $_GET['email'] ?? null;
    if (!$email) {
        if (isset($_GET['all']) && $_GET['all'] === 'true') {
            try {
                $users = $userModel->getAllUsers();
                json_response($users);
            } catch (PDOException $e) {
                json_response(['error' => 'Database error: ' . $e->getMessage()], 500);
            }
        } else {
            json_response(['error' => 'Email query parameter is required'], 400);
        }
    }

    try {
        $user = $userModel->findByEmail($email);
        if ($user) {
            json_response([
                'id' => $user['id'],
                'username' => $user['username'],
                'name' => $user['name'],
                'lastName' => $user['lastName'],
                'email' => $user['email']
            ]);
        } else {
            json_response(['error' => 'User not found'], 404);
        }
    } catch (PDOException $e) {
        json_response(['error' => 'Database error: ' . $e->getMessage()], 500);
    }
}

if ($method === 'GET' && preg_match('#^/users/([\w.-]+@[\w.-]+\.\w+)$#', $uri, $matches)) { // Find by email via path
    $email = $matches[1];
    $user = $userModel->findByEmail($email);
    if ($user) {
        unset($user['password']);
        json_response($user);
    } else {
        json_response(['error' => 'User not found by email in path'], 404);
    }
} elseif ($method === 'GET' && preg_match('#^/users/([\w-]+)$#', $uri, $matches)) { // Find by username via path
    $username = $matches[1];
    $user = $userModel->findByUsername($username);
    if ($user) {
        unset($user['password']);
        json_response($user);
    } else {
        json_response(['error' => 'User not found by username in path'], 404);
    }
}


if (!headers_sent()) {
    json_response(['error' => 'Endpoint not found', 'uri_debug' => $uri, 'method_debug' => $method], 404);
}