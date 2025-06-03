<?php
namespace Models;

use PDO;

class UserModel {
    private $pdo;

    public function __construct(PDO $pdo) {
        $this->pdo = $pdo;
    }

    public function create($password, $name, $lastName, $email) {
        $stmt = $this->pdo->prepare("INSERT INTO users (password, name, lastName, email) VALUES (?, ?, ?, ?)");
        if ($stmt->execute([$password, $name, $lastName, $email])) {
            return $this->pdo->lastInsertId();
        }
        return false;
    }

    public function findByEmail($email) {
        $stmt = $this->pdo->prepare("SELECT * FROM users WHERE email = ?");
        $stmt->execute([$email]);
        return $stmt->fetch(PDO::FETCH_ASSOC);
    }

    public function findById($id) {
        $stmt = $this->pdo->prepare("SELECT * FROM users WHERE id = ?");
        $stmt->execute([$id]);
        return $stmt->fetch(PDO::FETCH_ASSOC);
    }

    public function getAllUsers() {
        $stmt = $this->pdo->query("SELECT id, name, lastName, email FROM users");
        return $stmt->fetchAll(PDO::FETCH_ASSOC);
    }

    public function updatePassword($email, $password) {
        $stmt = $this->pdo->prepare("UPDATE users SET password = ? WHERE email = ?");
        return $stmt->execute([$password, $email]);
    }

    public function delete($email) {
        $stmt = $this->pdo->prepare("DELETE FROM users WHERE email = ?");
        return $stmt->execute([$email]);
    }
}
