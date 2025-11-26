
-- =============================================
-- 1. Tabelas de Apoio e Estrutura
-- =============================================

CREATE TABLE Categoria (
    id_categoria INT PRIMARY KEY,
    nome VARCHAR(50) NOT NULL CHECK (nome IN ('Popular', 'Plus', 'Premium')),
    valor_diaria_atual DECIMAL(10, 2) NOT NULL -- Preço vigente hoje
);

CREATE TABLE Cidade (
    id_cidade INT PRIMARY KEY,
    nome VARCHAR(100) NOT NULL,
    uf CHAR(2) NOT NULL
);

CREATE TABLE Loja (
    id_loja INT PRIMARY KEY,
    nome_unidade VARCHAR(100) NOT NULL,
    id_cidade INT NOT NULL,
    FOREIGN KEY (id_cidade) REFERENCES Cidade(id_cidade)
);

-- =============================================
-- 2. Atores do Sistema
-- =============================================

CREATE TABLE Funcionario (
    id_funcionario INT PRIMARY KEY,
    nome VARCHAR(100) NOT NULL,
    cargo VARCHAR(20) CHECK (cargo IN ('Atendente', 'Gerente')),
    id_loja INT NOT NULL,
    FOREIGN KEY (id_loja) REFERENCES Loja(id_loja)
);

CREATE TABLE Cliente (
    id_cliente INT PRIMARY KEY,
    nome_completo VARCHAR(150) NOT NULL,
    cpf VARCHAR(14) UNIQUE NOT NULL,
    cnh VARCHAR(20) UNIQUE NOT NULL,
    cnh_validade DATE NOT NULL, -- Regra: Bloquear se data < hoje
    data_nascimento DATE NOT NULL,
    endereco_completo VARCHAR(255) NOT NULL,
    token_cartao_credito VARCHAR(100) NOT NULL, -- Segurança PCI (apenas token)
    email VARCHAR(100) NOT NULL
);

-- =============================================
-- 3. Frota
-- =============================================

CREATE TABLE Veiculo (
    id_veiculo INT PRIMARY KEY,
    placa VARCHAR(10) UNIQUE NOT NULL,
    fabricante VARCHAR(50) NOT NULL,
    modelo VARCHAR(50) NOT NULL,
    ano INT NOT NULL,
    cor VARCHAR(30) NOT NULL,
    km_atual INT DEFAULT 0,
    status_atual VARCHAR(20) DEFAULT 'Pátio' 
        CHECK (status_atual IN ('Pátio', 'Em Locação', 'Manutenção', 'Inativo')),
    id_categoria INT NOT NULL,
    id_loja_atual INT NOT NULL,
    FOREIGN KEY (id_categoria) REFERENCES Categoria(id_categoria),
    FOREIGN KEY (id_loja_atual) REFERENCES Loja(id_loja)
);

-- =============================================
-- 4. Operação de Locação (Core)
-- =============================================

CREATE TABLE Locacao (
    id_locacao INT PRIMARY KEY,
    codigo_reserva VARCHAR(20) UNIQUE NOT NULL, -- Ex: 'RES-998877'
    
    id_cliente INT NOT NULL,
    id_veiculo INT NOT NULL,
    id_funcionario_retirada INT, -- Null se for reserva online
    
    -- Regra de Ouro: Snapshot de Preço
    valor_diaria_acordado DECIMAL(10, 2) NOT NULL, 
    
    -- Datas
    data_reserva DATETIME DEFAULT CURRENT_TIMESTAMP,
    data_retirada_agendada DATETIME NOT NULL,
    data_retirada_real DATETIME,
    data_devolucao_agendada DATETIME NOT NULL,
    data_devolucao_real DATETIME,
    
    -- Logística
    id_loja_retirada INT NOT NULL,
    id_loja_devolucao_prevista INT NOT NULL,
    id_loja_devolucao_real INT,

    status_locacao VARCHAR(20) DEFAULT 'Agendada'
        CHECK (status_locacao IN ('Agendada', 'Ativa', 'Finalizada', 'Cancelada')),

    FOREIGN KEY (id_cliente) REFERENCES Cliente(id_cliente),
    FOREIGN KEY (id_veiculo) REFERENCES Veiculo(id_veiculo),
    FOREIGN KEY (id_funcionario_retirada) REFERENCES Funcionario(id_funcionario),
    FOREIGN KEY (id_loja_retirada) REFERENCES Loja(id_loja),
    FOREIGN KEY (id_loja_devolucao_real) REFERENCES Loja(id_loja)
);

-- =============================================
-- 5. Financeiro (Auditoria e Múltiplos Pagamentos)
-- =============================================

CREATE TABLE LancamentoFinanceiro (
    id_lancamento INT PRIMARY KEY,
    id_locacao INT NOT NULL,
    tipo_lancamento VARCHAR(30) NOT NULL 
        CHECK (tipo_lancamento IN ('Diarias', 'Taxa Reagendamento', 'Multa Cancelamento', 'Taxa Devolução', 'Taxa Extensão', 'Avaria')),
    valor DECIMAL(10, 2) NOT NULL,
    data_lancamento DATETIME DEFAULT CURRENT_TIMESTAMP,
    status_pagamento VARCHAR(20) DEFAULT 'Pendente' 
        CHECK (status_pagamento IN ('Pendente', 'Pago', 'Estornado')),
    
    FOREIGN KEY (id_locacao) REFERENCES Locacao(id_locacao)
);

-- =============================================
-- 6. Manutenção
-- =============================================

CREATE TABLE Manutencao (
    id_manutencao INT PRIMARY KEY,
    id_veiculo INT NOT NULL,
    id_locacao_origem INT, -- Nullable (Manutenção preventiva não tem locação)
    data_entrada DATETIME DEFAULT CURRENT_TIMESTAMP,
    data_saida DATETIME,
    custo_total DECIMAL(10, 2) NOT NULL,
    descricao_servicos TEXT,
    km_veiculo_momento INT NOT NULL,
    tipo VARCHAR(20) CHECK (tipo IN ('Preventiva', 'Corretiva', 'Pós-Locação')),
    
    FOREIGN KEY (id_veiculo) REFERENCES Veiculo(id_veiculo),
    FOREIGN KEY (id_locacao_origem) REFERENCES Locacao(id_locacao)
);


-- Scripts Operacionais (Exemplos de Uso)

-- 1. Obter o preço atual da categoria 'Plus' (ID 2)
-- Digamos que retorne 150.00

-- 2. Inserir a reserva travando esse preço
INSERT INTO Locacao (
    id_locacao, codigo_reserva, id_cliente, id_veiculo, 
    valor_diaria_acordado, -- AQUI ESTÁ O SEGREDO
    data_retirada_agendada, data_devolucao_agendada, 
    id_loja_retirada, id_loja_devolucao_prevista
) VALUES (
    1001, 'RES-2023-A', 50, 200, 
    150.00, -- Preço congelado. Se a categoria subir para 200 amanhã, essa reserva mantém 150.
    '2023-12-01 08:00:00', '2023-12-05 18:00:00',
    1, 1
);

-- 3. Gerar a cobrança inicial (Diárias)
INSERT INTO LancamentoFinanceiro (id_lancamento, id_locacao, tipo_lancamento, valor, status_pagamento)
VALUES (5001, 1001, 'Diarias', (150.00 * 5), 'Pago');

-- Devolução em Local Diferente (Cobrança de Taxa)
-- Regra: Cliente devolve na Loja 2, mas pegou na Loja 1. Cobra taxa.
-- 1. Atualizar a locação finalizando
UPDATE Locacao 
SET data_devolucao_real = NOW(),
    id_loja_devolucao_real = 2, -- Loja diferente da prevista
    status_locacao = 'Finalizada'
WHERE id_locacao = 1001;

-- 2. Atualizar local do carro
UPDATE Veiculo SET id_loja_atual = 2, status_atual = 'Pátio' WHERE id_veiculo = 200;

-- 3. Inserir cobrança da taxa de retorno (Auditoria)
INSERT INTO LancamentoFinanceiro (id_lancamento, id_locacao, tipo_lancamento, valor, status_pagamento)
VALUES (5002, 1001, 'Taxa Devolução', 120.00, 'Pendente'); 
-- Sistema tenta cobrar o cartão tokenizado e depois muda para 'Pago'


-- Relatórios Gerenciais (Versão Enterprise)
SELECT 
    v.modelo,
    v.placa,
    COALESCE(Receita.total_ganho, 0) AS total_receita,
    COALESCE(Custo.total_gasto, 0) AS total_custo,
    (COALESCE(Receita.total_ganho, 0) - COALESCE(Custo.total_gasto, 0)) AS lucro_liquido
FROM Veiculo v
-- Subquery para Receita (Soma apenas pagamentos efetivados)
LEFT JOIN (
    SELECT l.id_veiculo, SUM(lf.valor) as total_ganho
    FROM Locacao l
    JOIN LancamentoFinanceiro lf ON l.id_locacao = lf.id_locacao
    WHERE lf.status_pagamento = 'Pago'
    GROUP BY l.id_veiculo
) Receita ON v.id_veiculo = Receita.id_veiculo
-- Subquery para Custo (Manutenções)
LEFT JOIN (
    SELECT id_veiculo, SUM(custo_total) as total_gasto
    FROM Manutencao
    GROUP BY id_veiculo
) Custo ON v.id_veiculo = Custo.id_veiculo
ORDER BY lucro_liquido DESC;

--Relatório 2: Unidades Mais Lucrativas (Faturamento)
--Considera onde o dinheiro foi gerado (Loja de Retirada).

SELECT 
    loja.nome_unidade,
    COUNT(DISTINCT l.id_locacao) AS qtd_locacoes,
    SUM(lf.valor) AS faturamento_total
FROM Loja loja
JOIN Locacao l ON loja.id_loja = l.id_loja_retirada
JOIN LancamentoFinanceiro lf ON l.id_locacao = lf.id_locacao
WHERE lf.status_pagamento = 'Pago'
GROUP BY loja.nome_unidade
ORDER BY faturamento_total DESC;

