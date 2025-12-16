# 🔄 Diagrama de Arquitectura: Ciclo Económico de Antigravity Poker

## Diagrama de Flujo Completo

```mermaid
flowchart TD
    Start([Usuario con Billetera]) --> CheckBalance{¿Tiene<br/>suficiente<br/>balance?}
    
    CheckBalance -->|No| Insufficient[❌ Error:<br/>Balance Insuficiente]
    CheckBalance -->|Sí| JoinTable[joinTable]
    
    JoinTable --> ValidateRoom{¿roomId<br/>válido?}
    ValidateRoom -->|No 'new_room'| ErrorInvalid[❌ Error:<br/>Room ID Inválido]
    ValidateRoom -->|Sí| CheckSession{¿Sesión<br/>activa<br/>existe?}
    
    CheckSession -->|Sí| ReturnExisting[✅ Retornar<br/>Sesión Existente<br/>IDEMPOTENCIA]
    CheckSession -->|No| CreateSession[Crear Nueva Sesión]
    
    CreateSession --> DeductBuyIn[Descontar BuyIn<br/>credit -= buyInAmount]
    DeductBuyIn --> SetState[Establecer Estado<br/>moneyInPlay = buyInAmount<br/>currentTableId = tableId]
    SetState --> CreateSessionDoc[Crear poker_sessions<br/>status: 'active']
    CreateSessionDoc --> LogDebit[Registrar en<br/>transaction_logs<br/>type: 'debit']
    
    ReturnExisting --> InGame[🎮 Usuario en Mesa]
    CreateSessionDoc --> InGame
    LogDebit --> InGame
    
    InGame --> PlayHand[Jugar Mano]
    PlayHand --> UpdateChips[Actualizar Fichas<br/>poker_tables.players[].chips<br/>FUENTE DE VERDAD]
    
    UpdateChips --> CheckWin{¿Ganó<br/>la mano?}
    CheckWin -->|No| PlayHand
    CheckWin -->|Sí| SettleRound[settleGameRound]
    
    SettleRound --> CalculatePot[Calcular Pot Total]
    CalculatePot --> CalculateRake[Calcular Rake<br/>Rake = Pot * 0.08]
    CalculateRake --> CheckTableType{¿Mesa<br/>Pública?}
    
    CheckTableType -->|Privada| DistributePrivate[Distribuir Rake<br/>100% → Plataforma<br/>system_stats.accumulated_rake]
    CheckTableType -->|Pública| DistributePublic[Distribuir Rake<br/>50% → Plataforma<br/>30% → Club Owner<br/>20% → Seller]
    
    DistributePrivate --> UpdateWinnerStack[Actualizar Stack Ganador<br/>poker_tables.players[].chips<br/>+= Pot - Rake]
    DistributePublic --> UpdateWinnerStack
    
    UpdateWinnerStack --> UpdateSession[Actualizar Sesión<br/>totalRakePaid += rake]
    UpdateSession --> LogWin[Registrar en<br/>financial_ledger<br/>type: 'GAME_WIN']
    LogWin --> PlayHand
    
    InGame --> CashOut[processCashOut]
    
    CashOut --> FindSession{¿Sesión<br/>activa<br/>existe?}
    FindSession -->|No| ErrorNoSession[❌ Error:<br/>No se encontró<br/>sesión activa<br/>PROHIBIDO CREAR]
    FindSession -->|Sí| ReadChips[Leer Fichas de Mesa<br/>poker_tables.players[].chips<br/>FUENTE DE VERDAD]
    
    ReadChips --> CalculateGross[Calcular GrossProfit<br/>GrossProfit = FichasFinales - BuyIn]
    CalculateGross --> CheckProfit{¿GrossProfit<br/>> 0?}
    
    CheckProfit -->|No| NoRake[Rake = 0<br/>Payout = FichasFinales]
    CheckProfit -->|Sí| CalculateExitRake[Calcular Rake de Salida<br/>Rake = GrossProfit * 0.08]
    
    CalculateExitRake --> CheckTableType2{¿Mesa<br/>Pública?}
    CheckTableType2 -->|Privada| DistributeExitPrivate[Distribuir Rake<br/>100% → Plataforma]
    CheckTableType2 -->|Pública| DistributeExitPublic[Distribuir Rake<br/>50% → Plataforma<br/>30% → Club Owner<br/>20% → Seller]
    
    DistributeExitPrivate --> CalculatePayout[Calcular Payout<br/>Payout = FichasFinales - Rake]
    DistributeExitPublic --> CalculatePayout
    NoRake --> CalculatePayout
    
    CalculatePayout --> TransferCredit[Transferir a Billetera<br/>credit += Payout]
    TransferCredit --> CleanState[LIMPIEZA OBLIGATORIA<br/>moneyInPlay = 0<br/>currentTableId = null]
    
    CleanState --> CloseSession[Cerrar Sesión<br/>poker_sessions<br/>status: 'completed']
    CloseSession --> ClearTableChips[Limpiar Fichas en Mesa<br/>poker_tables.players[].chips = 0]
    ClearTableChips --> LogCashOut[Registrar en<br/>financial_ledger<br/>type: 'SESSION_END']
    LogCashOut --> LogCredit[Registrar en<br/>transaction_logs<br/>type: 'credit']
    LogCredit --> End([✅ Usuario fuera de Mesa<br/>Dinero en Billetera])
    
    style Start fill:#e1f5ff
    style End fill:#d4edda
    style ErrorInvalid fill:#f8d7da
    style ErrorNoSession fill:#f8d7da
    style Insufficient fill:#f8d7da
    style InGame fill:#fff3cd
    style CleanState fill:#d1ecf1
    style ReturnExisting fill:#d4edda
    style ReadChips fill:#d1ecf1
    style DistributePrivate fill:#cfe2ff
    style DistributePublic fill:#cfe2ff
    style DistributeExitPrivate fill:#cfe2ff
    style DistributeExitPublic fill:#cfe2ff
```

---

## Diagrama de Distribución del Rake

```mermaid
flowchart LR
    Pot[Pot Total<br/>Ej: 1000] --> CalculateRake[Calcular Rake<br/>8% = 80]
    
    CalculateRake --> CheckType{¿Tipo<br/>de Mesa?}
    
    CheckType -->|Privada| PrivateFlow[100% Plataforma<br/>80 → system_stats]
    CheckType -->|Pública| PublicFlow[Distribución<br/>50/30/20]
    
    PublicFlow --> Platform[50% Plataforma<br/>40 → system_stats]
    PublicFlow --> Club[30% Club Owner<br/>24 → clubs.walletBalance]
    PublicFlow --> Seller[20% Seller<br/>16 → users.credit]
    
    PrivateFlow --> EndPrivate[✅ Rake Distribuido]
    Platform --> EndPublic[✅ Rake Distribuido]
    Club --> EndPublic
    Seller --> EndPublic
    
    style Pot fill:#e1f5ff
    style CalculateRake fill:#fff3cd
    style PrivateFlow fill:#cfe2ff
    style Platform fill:#cfe2ff
    style Club fill:#cfe2ff
    style Seller fill:#cfe2ff
    style EndPrivate fill:#d4edda
    style EndPublic fill:#d4edda
```

---

## Diagrama de Estados del Usuario

```mermaid
stateDiagram-v2
    [*] --> Wallet: Usuario con Billetera
    
    Wallet --> Joining: joinTable()
    Joining --> InGame: Sesión Creada/Existente
    
    InGame --> Playing: Jugar Mano
    Playing --> Settling: Ganar Mano
    Settling --> InGame: Rake Distribuido
    
    InGame --> CashingOut: processCashOut()
    CashingOut --> Cleaning: Payout Calculado
    Cleaning --> Wallet: Estado Limpiado<br/>moneyInPlay = 0<br/>currentTableId = null
    
    note right of Joining
        Regla: Idempotencia
        Máximo 1 sesión activa
    end note
    
    note right of CashingOut
        Regla: Fuente de Verdad
        Fichas de poker_tables
        NO crear sesiones nuevas
    end note
    
    note right of Cleaning
        Regla: Limpieza Obligatoria
        Siempre limpiar estado
    end note
```

---

## Diagrama de Colecciones y Relaciones

```mermaid
erDiagram
    USERS ||--o{ POKER_SESSIONS : "tiene"
    USERS ||--o{ TRANSACTION_LOGS : "genera"
    USERS ||--o{ FINANCIAL_LEDGER : "registra"
    POKER_TABLES ||--o{ POKER_SESSIONS : "contiene"
    POKER_TABLES ||--o{ FINANCIAL_LEDGER : "genera"
    CLUBS ||--o{ POKER_TABLES : "crea"
    USERS ||--o| CLUBS : "pertenece"
    USERS ||--o| USERS : "seller"
    SYSTEM_STATS ||--o{ FINANCIAL_LEDGER : "acumula"
    
    USERS {
        string uid PK
        number credit
        number moneyInPlay
        string currentTableId
        string clubId FK
        string sellerId FK
    }
    
    POKER_SESSIONS {
        string sessionId PK
        string userId FK
        string roomId FK
        number buyInAmount
        number currentChips
        number totalRakePaid
        number netResult
        number exitFee
        string status
    }
    
    POKER_TABLES {
        string tableId PK
        array players
        boolean isPublic
        number minBuyIn
    }
    
    FINANCIAL_LEDGER {
        string ledgerId PK
        string userId FK
        string tableId FK
        string type
        number amount
        number netAmount
        number netProfit
        number grossAmount
        number rakePaid
        number buyInAmount
    }
    
    SYSTEM_STATS {
        string docId PK
        number accumulated_rake
    }
    
    CLUBS {
        string clubId PK
        number walletBalance
    }
    
    TRANSACTION_LOGS {
        string logId PK
        string userId FK
        number amount
        string type
    }
```

---

## Flujo de Datos: Ejemplo Completo

```mermaid
sequenceDiagram
    participant U as Usuario
    participant J as joinTable()
    participant DB as Firestore
    participant S as settleGameRound()
    participant C as processCashOut()
    
    U->>J: joinTable(roomId, buyInAmount)
    J->>DB: Verificar sesión activa
    alt Sesión existe
        DB-->>J: Sesión existente
        J-->>U: Retornar sessionId existente
    else No existe
        J->>DB: Descontar buyInAmount
        DB->>DB: users.credit -= buyInAmount
        DB->>DB: users.moneyInPlay = buyInAmount
        DB->>DB: users.currentTableId = roomId
        DB->>DB: Crear poker_sessions (active)
        J-->>U: Nueva sesión creada
    end
    
    U->>S: settleGameRound(potTotal, winnerUid)
    S->>DB: Leer poker_tables
    S->>S: Calcular rake (8% del pot)
    alt Mesa Privada
        S->>DB: system_stats.accumulated_rake += 100% rake
    else Mesa Pública
        S->>DB: system_stats.accumulated_rake += 50% rake
        S->>DB: clubs.walletBalance += 30% rake
        S->>DB: users.credit (seller) += 20% rake
    end
    S->>DB: poker_tables.players[].chips += pot - rake
    S->>DB: poker_sessions.totalRakePaid += rake
    S-->>U: Mano liquidada
    
    U->>C: processCashOut(tableId)
    C->>DB: Buscar sesión activa
    C->>DB: Leer fichas de poker_tables (FUENTE DE VERDAD)
    C->>C: Calcular GrossProfit = FichasFinales - BuyIn
    C->>C: Calcular Rake = GrossProfit * 0.08
    alt Mesa Privada
        C->>DB: system_stats.accumulated_rake += 100% rake
    else Mesa Pública
        C->>DB: system_stats.accumulated_rake += 50% rake
        C->>DB: clubs.walletBalance += 30% rake
        C->>DB: users.credit (seller) += 20% rake
    end
    C->>DB: users.credit += Payout
    C->>DB: users.moneyInPlay = 0
    C->>DB: users.currentTableId = null
    C->>DB: poker_sessions.status = 'completed'
    C->>DB: poker_tables.players[].chips = 0
    C-->>U: Cashout completado
```

---

## Leyenda

- 🟢 **Verde:** Operaciones exitosas
- 🟡 **Amarillo:** Procesos en curso
- 🔵 **Azul:** Distribución de rake
- 🔴 **Rojo:** Errores o validaciones fallidas
- ⚪ **Blanco:** Estados intermedios

---

**Última actualización:** 2024  
**Versión:** 1.0.0

