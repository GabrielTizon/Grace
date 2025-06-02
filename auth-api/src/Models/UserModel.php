<?php
namespace Models;

use PDO;

class UserModel {
    private $pdo;

    public function __construct($pdo) {
        $this->pdo = $pdo;
    }

    public function create($username, $password, $name, $lastName, $email) {
        $stmt = $this->pdo->prepare("INSERT INTO users (username, password, name, lastName, email) VALUES (?, ?, ?, ?, ?)");
        if ($stmt->execute([$username, $password, $name, $lastName, $email])) {
            return $this->pdo->lastInsertId();
        }
        return false;
    }

    public function findByUsername($username) {
        $stmt = $this->pdo->prepare("SELECT * FROM users WHERE username = ?");
        $stmt->execute([$username]);
        return $stmt->fetch(PDO::FETCH_ASSOC);
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
        $stmt = $this->pdo->query("SELECT id, username, name, lastName, email FROM users");
        return $stmt->fetchAll(PDO::FETCH_ASSOC);
    }

    public function updatePassword($username, $password) {
        $stmt = $this->pdo->prepare("UPDATE users SET password = ? WHERE username = ?");
        return $stmt->execute([$password, $username]);
    }

    public function delete($username) {
        $stmt = $this->pdo->prepare("DELETE FROM users WHERE username = ?");
        return $stmt->execute([$username]);
    }
}