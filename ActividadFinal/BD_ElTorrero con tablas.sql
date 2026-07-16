CREATE DATABASE ElTorrero;
GO

USE ElTorrero;
GO

-- ROL
CREATE TABLE Rol (
    IdRol INT IDENTITY(1,1) PRIMARY KEY,
    Role VARCHAR(50) NOT NULL UNIQUE
);

-- EMPLEADOS (Rol 1 - N Empleados)
CREATE TABLE Empleados (
    IdEmpleado INT IDENTITY(1,1) PRIMARY KEY,
    Nombre VARCHAR(80) NOT NULL,
    Apellido VARCHAR(80) NOT NULL,
    Contacto VARCHAR(50),
    IdRol INT NOT NULL,
    FOREIGN KEY (IdRol) REFERENCES Rol(IdRol)
);

-- JORNADAS
CREATE TABLE Jornadas (
    IdJornada INT IDENTITY(1,1) PRIMARY KEY,
    TipoJornada VARCHAR(50) NOT NULL
);

-- HORARIOS (ternaria Horario-Empleado-Jornada resuelta con FK directas)
CREATE TABLE Horarios (
    IdHorario INT IDENTITY(1,1) PRIMARY KEY,
    FechaIngresa TIME NOT NULL,
    FechaSalida TIME NOT NULL,
    IdEmpleado INT NOT NULL,
    IdJornada INT NOT NULL,
    FOREIGN KEY (IdEmpleado) REFERENCES Empleados(IdEmpleado),
    FOREIGN KEY (IdJornada) REFERENCES Jornadas(IdJornada),
    CHECK (FechaSalida > FechaIngresa)
);

-- SALARIOEMPLEADOS (llave compuesta: un empleado tiene N registros, uno por mes)
CREATE TABLE SalarioEmpleados (
    IdEmpleado INT NOT NULL,
    FechaAñoMes DATE NOT NULL,
    Salario DECIMAL(10,2) NOT NULL CHECK (Salario > 0),
    PRIMARY KEY (IdEmpleado, FechaAñoMes),
    FOREIGN KEY (IdEmpleado) REFERENCES Empleados(IdEmpleado)
);

-- PROVEEDORES
CREATE TABLE Proveedores (
    IdProveedor INT IDENTITY(1,1) PRIMARY KEY,
    Nombre VARCHAR(100) NOT NULL,
    Contacto VARCHAR(50)
);

-- PRODUCTOS (Proveedor 1 - N Productos)
CREATE TABLE Productos (
    IdProducto INT IDENTITY(1,1) PRIMARY KEY,
    Nombre VARCHAR(80) NOT NULL,
    Precio DECIMAL(10,2) NOT NULL CHECK (Precio >= 0),
    IdProveedor INT NOT NULL,
    FOREIGN KEY (IdProveedor) REFERENCES Proveedores(IdProveedor)
);

-- INVENTARIO (Producto 1 - N Inventario, movimientos de stock)
CREATE TABLE Inventario (
    IdInventario INT IDENTITY(1,1) PRIMARY KEY,
    Cantidad INT NOT NULL DEFAULT 0 CHECK (Cantidad >= 0),
    IdProducto INT NOT NULL,
    FOREIGN KEY (IdProducto) REFERENCES Productos(IdProducto)
);

-- CLIENTE
CREATE TABLE Cliente (
    IdCliente INT IDENTITY(1,1) PRIMARY KEY,
    Nombre VARCHAR(100) NOT NULL
);

-- MENU
CREATE TABLE Menu (
    IdMenu INT IDENTITY(1,1) PRIMARY KEY,
    NombreComida VARCHAR(100) NOT NULL,
    Precio DECIMAL(10,2) NOT NULL CHECK (Precio >= 0)
);

-- PEDIDOS (Empleado 1 - N Pedidos, Cliente 1 - N Pedidos)
CREATE TABLE Pedidos (
    IdPedido INT IDENTITY(1,1) PRIMARY KEY,
    MetodoPago VARCHAR(30) NOT NULL,
    TotalPedido DECIMAL(10,2) NOT NULL DEFAULT 0 CHECK (TotalPedido >= 0),
    IdEmpleado INT NOT NULL,
    IdCliente INT NOT NULL,
    FOREIGN KEY (IdEmpleado) REFERENCES Empleados(IdEmpleado),
    FOREIGN KEY (IdCliente) REFERENCES Cliente(IdCliente)
);

-- DETALLEPEDIDO (resuelve la N:M real entre Pedidos y Menu)
CREATE TABLE DetallePedido (
    IdPedido INT NOT NULL,
    IdMenu INT NOT NULL,
    Cantidad INT NOT NULL DEFAULT 1 CHECK (Cantidad > 0),
    PRIMARY KEY (IdPedido, IdMenu),
    FOREIGN KEY (IdPedido) REFERENCES Pedidos(IdPedido),
    FOREIGN KEY (IdMenu) REFERENCES Menu(IdMenu)
);

-- MOVIMIENTOS (un solo origen posible por fila)
CREATE TABLE Finanzas (
    IdFinanza INT IDENTITY(1,1) PRIMARY KEY,
    Origen VARCHAR(50) NOT NULL,
    Tipo VARCHAR(30) NOT NULL,
    Fecha DATE NOT NULL DEFAULT GETDATE(),
    Monto DECIMAL(10,2) NOT NULL,
    IdEmpleado INT,
    FechaAñoMesSalario DATE,
    IdInventario INT,
    FOREIGN KEY (IdEmpleado, FechaAñoMesSalario) REFERENCES SalarioEmpleados(IdEmpleado, FechaAñoMes),
    FOREIGN KEY (IdInventario) REFERENCES Inventario(IdInventario),
    CHECK (
        (IdEmpleado IS NOT NULL AND FechaAñoMesSalario IS NOT NULL AND IdInventario IS NULL)
        OR
        (IdEmpleado IS NULL AND FechaAñoMesSalario IS NULL AND IdInventario IS NOT NULL)
    )
);