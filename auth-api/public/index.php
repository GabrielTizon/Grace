<?php
require __DIR__ . '/../vendor/autoload.php';

use Slim\Factory\AppFactory;
use App\Controllers\AuthController;
use Dotenv\Dotenv;

// Carrega variáveis de ambiente
$dotenv = Dotenv::createImmutable(__DIR__ . '/../');
$dotenv->load();

$app = AppFactory::create();

// Rotas
$app->post('/register', [AuthController::class, 'register']);
$app->post('/login', [AuthController::class, 'login']);

// Healthcheck (para Docker)
$app->get('/health', function ($request, $response, $args) {
    $response->getBody()->write(json_encode(["status" => "ok"]));
    return $response->withHeader('Content-Type', 'application/json');
});

$app->run();
