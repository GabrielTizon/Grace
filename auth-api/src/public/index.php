<?php
require '/app/vendor/autoload.php';

use Firebase\JWT\JWT;

header('Content-Type: application/json');

$dsn = "pgsql:host=db;port=5432;dbname=mydb;user=user;password=password";
try {
    $pdo = new PDO($dsn);
    $pdo->setAttribute(PDO::ATTR_ERRMODE, PDO::ERRMODE_EXCEPTION);
} catch (PDOException $e) {
    http_response_code(500);
    echo json_encode(['error' => 'Database connection failed: ' . $e->getMessage()]);
    exit;
}

$input = json_decode(file_get_contents('php://input'), true);

$uri = $_SERVER['REQUEST_URI'] ?? '/';
$method = $_SERVER['REQUEST_METHOD'] ?? 'GET';
$jwtSecret = 'your_secret_key';

// REGISTER
if ($method === 'POST' && strpos($uri, '/register') !== false) {
    if (!isset($input['username'], $input['password'])) {
        http_response_code(400);
        echo json_encode(['error' => 'Username and password required']);
        exit;
    }

    $username = $input['username'];
    $password = password_hash($input['password'], PASSWORD_BCRYPT);

    try {
        $stmt = $pdo->prepare("INSERT INTO users (username, password) VALUES (?, ?)");
        if ($stmt->execute([$username, $password])) {
            $payload = ['username' => $username, 'exp' => time() + 3600];
            $jwt = JWT::encode($payload, $jwtSecret, 'HS256');
            echo json_encode(['token' => $jwt]);
        } else {
            http_response_code(400);
            echo json_encode(['error' => 'Registration failed']);
        }
    } catch (PDOException $e) {
        if (strpos($e->getMessage(), 'duplicate key') !== false) {
            http_response_code(400);
            echo json_encode(['error' => 'Username already exists']);
        } else {
            http_response_code(500);
            echo json_encode(['error' => 'Database error: ' . $e->getMessage()]);
        }
    }
    exit;
}

// LOGIN
if ($method === 'POST' && strpos($uri, '/login') !== false) {
    if (!isset($input['username'], $input['password'])) {
        http_response_code(400);
        echo json_encode(['error' => 'Username and password required']);
        exit;
    }

    $username = $input['username'];
    $password = $input['password'];

    try {
        $stmt = $pdo->prepare("SELECT * FROM users WHERE username = ?");
        $stmt->execute([$username]);
        $user = $stmt->fetch(PDO::FETCH_ASSOC);

        if ($user && password_verify($password, $user['password'])) {
            $payload = ['username' => $username, 'exp' => time() + 3600];
            $jwt = JWT::encode($payload, $jwtSecret, 'HS256');
            echo json_encode(['token' => $jwt]);
        } else {
            http_response_code(401);
            echo json_encode(['error' => 'Invalid credentials']);
        }
    } catch (PDOException $e) {
        http_response_code(500);
        echo json_encode(['error' => 'Database error: ' . $e->getMessage()]);
    }
    exit;
}

// DEFAULT: 404
http_response_code(404);
echo json_encode(['error' => 'File not found', 'uri' => $uri]);