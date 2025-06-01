<?php
require '/app/vendor/autoload.php';
use Firebase\JWT\JWT;

header('Content-Type: application/json');

// Conexão segura usando env
$host = getenv('DB_HOST') ?: 'db';
$dbname = getenv('DB_NAME') ?: 'mydb';
$user = getenv('DB_USER') ?: 'user';
$password = getenv('DB_PASS') ?: 'password';

$dsn = "pgsql:host=$host;port=5432;dbname=$dbname;user=$user;password=$password";

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

// GET USER
if ($method === 'GET' && preg_match('#^/user/([\w-]+)$#', $uri, $matches)) {
    $username = $matches[1];
    try {
        $stmt = $pdo->prepare("SELECT * FROM users WHERE username = ?");
        $stmt->execute([$username]);
        $user = $stmt->fetch(PDO::FETCH_ASSOC);
        if ($user) {
            echo json_encode($user);
        } else {
            http_response_code(404);
            echo json_encode(['error' => 'User not found']);
        }
    } catch (PDOException $e) {
        http_response_code(500);
        echo json_encode(['error' => 'Database error: ' . $e->getMessage()]);
    }
    exit;
}

// UPDATE USER PASSWORD
if ($method === 'PUT' && preg_match('#^/user/([\w-]+)$#', $uri, $matches)) {
    $username = $matches[1];
    if (!isset($input['password'])) {
        http_response_code(400);
        echo json_encode(['error' => 'New password required']);
        exit;
    }
    $password = password_hash($input['password'], PASSWORD_BCRYPT);

    try {
        $stmt = $pdo->prepare("UPDATE users SET password = ? WHERE username = ?");
        if ($stmt->execute([$password, $username])) {
            echo json_encode(['message' => 'Password updated']);
        } else {
            http_response_code(400);
            echo json_encode(['error' => 'Update failed']);
        }
    } catch (PDOException $e) {
        http_response_code(500);
        echo json_encode(['error' => 'Database error: ' . $e->getMessage()]);
    }
    exit;
}

// DELETE USER
if ($method === 'DELETE' && preg_match('#^/user/([\w-]+)$#', $uri, $matches)) {
    $username = $matches[1];
    try {
        $stmt = $pdo->prepare("DELETE FROM users WHERE username = ?");
        if ($stmt->execute([$username])) {
            echo json_encode(['message' => 'User deleted']);
        } else {
            http_response_code(400);
            echo json_encode(['error' => 'Delete failed']);
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
