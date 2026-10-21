-- ============================================
-- FreshBox SpA - Base de Datos (RDS MySQL)
-- Evaluación Parcial 2 - Arquitectura Cloud ARY1102
-- ============================================
-- Ejecutar en RDS MySQL Multi-AZ via mysql client
-- Conexion: mysql -h <RDS_ENDPOINT> -u alumno -palumno123

CREATE DATABASE IF NOT EXISTS freshbox_db;
USE freshbox_db;

-- Tabla de productos organicos y saludables
CREATE TABLE IF NOT EXISTS productos (
    id INT AUTO_INCREMENT PRIMARY KEY,
    nombre VARCHAR(255) NOT NULL,
    descripcion TEXT,
    precio DECIMAL(10,2) NOT NULL,
    stock INT NOT NULL DEFAULT 0,
    categoria VARCHAR(100),
    imagen_url VARCHAR(500),
    created_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP,
    updated_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP ON UPDATE CURRENT_TIMESTAMP
);

-- Datos de prueba: 5 productos organicos
INSERT INTO productos (nombre, descripcion, precio, stock, categoria) VALUES
('Manzanas Organicas', 'Manzanas frescas cultivadas sin pesticidas, malla 1 kg', 2500.00, 100, 'Frutas'),
('Palta Hass de Exportacion', 'Paltas cremosas de primera seleccion, 1 kg', 4990.00, 50, 'Verduras'),
('Miel de Abeja Natural', 'Miel 100% cruda y natural de bosque nativo, 500g', 6500.00, 80, 'Despensa'),
('Quinoa Blanca Organica', 'Quinoa lavada lista para cocinar, alta en proteinas, 500g', 3200.00, 120, 'Cereales'),
('Lechuga Hidroponica', 'Lechuga fresca cultivada en agua, libre de tierra y quimicos', 1200.00, 40, 'Verduras');

-- 2026 - Disenador asignatura: Ignacio A. Pastenet M.