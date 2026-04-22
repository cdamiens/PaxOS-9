-- ============================================================================
--                              SNAKE - PAXOPHONE
-- ============================================================================
-- Jeu du Snake adapté pour le Paxophone
--
-- Commandes tactiles : Toucher l'écran par rapport au centre pour choisir
-- la direction (haut/bas/gauche/droite)
--
-- Score :
--   - Chaque nourriture rapporte entre 10 et 100 pts selon l'efficacité
--     (100 - mouvements_depuis_dernier_repas * 2, minimum 10)
--   - Bonus +5 pts par segment supplémentaire du serpent
--   - Score toujours croissant (jamais négatif)
--
-- Vitesse :
--   - Commence à 400ms, diminue de 10ms par segment
--   - Plafond à 100ms
--   - Affichée via des chevrons (1 à 5)
--
-- NOTE IMPORTANTE - BUG ESP32:
-- NE JAMAIS utiliser time:removeInterval() ou time:removeTimeout() dans un callback Lua!
-- Cela cause un crash "LoadProhibited" sur ESP32 car le callback FreeRTOS sous-jacent
-- pointe vers l'objet supprimé.
-- Solution: Utiliser un intervalle fixe et gérer la logique de timing via time:monotonic().
-- Pour les timeout différés, ne pas les supprimer dans cleanup: le système les nettoie automatiquement.
-- ============================================================================

-- ============================================================================
-- DÉCLARATIONS ANTICIPÉES (forward declarations)
-- Nécessaires pour les fonctions qui se référencent mutuellement
-- ============================================================================
local afficheEcranAccueil, afficheEcranGameOver, afficheEcranInstructions, afficheEcranSettings, afficheEcranJeu

-- ============================================================================
-- VARIABLES DE JEU
-- ============================================================================
local int = math.floor              -- alias local, évite le lookup global répété
local direction = "down"            -- Direction actuelle du serpent
local oldWin                        -- Fenêtre précédente pour cleanup
local rythme                        -- ID intervalle de rendu
local gameRunning = false           -- État du jeu
local gameOverTimeout               -- Timeout différé pour écran game over (nettoyé automatiquement)
local lastMoveTime = 0              -- Timestamp dernier mouvement (gère la vitesse)
local directionChanged = false      -- Flag pour mouvement immédiat au touch

local statusBar                     -- Barre de statut (score en jeu)
local drawRect_canvas               -- Canvas de la zone de jeu
local snake = {}                    -- Corps du serpent (liste de tables {x, y})
local food = {x = 0, y = 0}        -- Position nourriture (table réutilisée, jamais réallouée)
local headCell = {x = 0, y = 0}    -- Calcul tête pré-alloué (évite alloc à chaque mouvement)
local bodySet = {}                  -- Lookup O(1) pour collision corps : clé = x*1000+y
local foodDirty = true              -- Nourriture à redessiner ?
local pixCoord = {}                 -- Coordonnées pixel pré-calculées (évite multiplications en hot path)
local lastDisplayedScore = -1       -- Cache pour éviter setText inutiles
local lastDisplayedSpeed = -1       -- Cache pour éviter setText inutiles
local movesSinceFood = 0            -- Mouvements depuis le dernier repas (calcul score)
local gameOverPending = false       -- Animation de mort en cours
local flashState = 0                -- Demi-flash courant (1-6, soit 3 clignotements)

-- ============================================================================
-- PRÉFÉRENCES UTILISATEUR
-- ============================================================================

local prefs = {
    language = "fr",
    difficulty = "easy"
}

local strings = {
    fr = {
        title = "Snake",
        play = "Jouer",
        quit = "Quitter",
        settings = "Paramètres",
        instructions = "Instructions",
        difficulty = "Difficulté",
        easy = "Facile",
        medium = "Moyen",
        hard = "Difficile",
        back = "Retour",
        titleInstructions = "Comment jouer",
        instructionText = "Touchez l'écran par rapport au centre pour choisir la direction du serpent",
        titleSettings = "Paramètres",
        language = "Langue",
        start = "Commencer"
    },
    en = {
        title = "Snake",
        play = "Play",
        quit = "Quit",
        settings = "Settings",
        instructions = "Instructions",
        difficulty = "Difficulty",
        easy = "Easy",
        medium = "Medium",
        hard = "Hard",
        back = "Back",
        titleInstructions = "How to play",
        instructionText = "Touch the screen relative to the center to choose the snake's direction",
        titleSettings = "Settings",
        language = "Language",
        start = "Start"
    }
}

local difficultyConfig = {
    easy   = { speed = 400, snakeColor = COLOR_GREEN,  borderColor = COLOR_GREEN  },
    medium = { speed = 300, snakeColor = COLOR_YELLOW, borderColor = COLOR_YELLOW },
    hard   = { speed = 200, snakeColor = COLOR_RED,    borderColor = COLOR_RED    }
}

-- ============================================================================
-- COULEURS DU JEU
-- ============================================================================
local COLOR_BORDER       = COLOR_YELLOW
local COLOR_BACKGROUND   = COLOR_DARK
local COLOR_SNAKE        = COLOR_GREEN
local COLOR_FOOD         = COLOR_RED
local COLOR_INGAME_SCORE = COLOR_GREEN
local COLOR_FINAL_SCORE  = COLOR_GREEN
local COLOR_FINAL_MAX    = COLOR_YELLOW
local COLOR_BUTTON       = COLOR_LIGHT_GREY

-- ============================================================================
-- FONCTIONS HELPER
-- ============================================================================

local function cleanupGame()
    if rythme then
        time:removeInterval(rythme)
        rythme = nil
    end
    -- gameOverTimeout n'est pas supprimé ici : le callback est peut-être en cours d'exécution.
    -- Le système le nettoiera automatiquement après son exécution.
    gameOverTimeout = nil
    lastMoveTime = 0
    directionChanged = false
    gameRunning = false
    lastDisplayedScore = -1
    lastDisplayedSpeed = -1
    movesSinceFood = 0
    gameOverPending = false
    flashState = 0
end

local function createButton(parent, x, y, width, height, text, onClick)
    local btn = gui:label(parent, x, y, width, height)
    btn:setFontSize(20)
    btn:setHorizontalAlignment(CENTER_ALIGNMENT)
    btn:setVerticalAlignment(CENTER_ALIGNMENT)
    btn:setBorderSize(1)
    btn:setRadius(10)
    btn:setBackgroundColor(COLOR_BUTTON)
    btn:setText(text)
    btn:onClick(onClick)
end

local function t(key)
    return strings[prefs.language][key]
end

local function loadPreferences()
    local success, result = pcall(loadTable, "snake_prefs.json")
    if success and result then
        prefs = result
    else
        prefs = { language = "fr", difficulty = "easy" }
        pcall(saveTable, "snake_prefs.json", prefs)
    end
end

local function savePreferences()
    pcall(saveTable, "snake_prefs.json", prefs)
end

local function applyDifficulty()
    local diff = difficultyConfig[prefs.difficulty]
    COLOR_SNAKE  = diff.snakeColor
    COLOR_BORDER = diff.borderColor
    GAME_SPEED   = diff.speed
end

-- ============================================================================
-- CONFIGURATION DE L'ÉCRAN
-- ============================================================================
local CELL_SIZE = 20
local GAP       = 2
local CASE_SIZE = CELL_SIZE - GAP

local STATUS_BAR_HEIGHT = 40
local SCREEN_WIDTH      = 320
local SCREEN_HEIGHT     = 480

local GAME_W = SCREEN_WIDTH
local GAME_H = SCREEN_HEIGHT - STATUS_BAR_HEIGHT

local cols     = int(GAME_W / CELL_SIZE)
local rows     = int(GAME_H / CELL_SIZE)
local paddingX = int((GAME_W - cols * CELL_SIZE) / 2)
local paddingY = int((GAME_H - rows * CELL_SIZE) / 2)

local gridSize = {w = cols, h = rows}

-- Pré-calcul des coordonnées pixel pour éviter multiplications et math.floor dans la boucle de jeu.
-- pixCoord[i] = coordonnée pixel de départ de la case i (i ∈ [1, max(cols,rows)])
do
    local maxDim = math.max(cols, rows) + 1
    for i = 1, maxDim do
        pixCoord[i] = (i - 1) * CELL_SIZE + 1
    end
end

-- ============================================================================
-- SYSTÈME DE SCORE
-- ============================================================================
local score    = 0
local maxScore = 0

-- ============================================================================
-- SYSTÈME DE VITESSE
-- ============================================================================
local GAME_SPEED     = 400
local SPEED_DECREASE = 10
local MIN_SPEED      = 100

local function getSpeed()
    if not snake or #snake == 0 then return GAME_SPEED end
    return math.max(GAME_SPEED - (#snake * SPEED_DECREASE), MIN_SPEED)
end

-- Retourne le nombre de chevrons (1-5) correspondant à la vitesse courante
local function getSpeedChevrons()
    local chevrons = int((GAME_SPEED - getSpeed()) / 60) + 1
    return math.min(chevrons, 5)
end

-- ============================================================================
-- GESTION DE FENÊTRES
-- ============================================================================
local function manageWindow()
    local win = gui:window()
    gui:setWindow(win)
    if oldWin then
        gui:del(oldWin)
        oldWin = nil
    end
    oldWin = win
    return win
end

-- ============================================================================
-- GESTION DE LA NOURRITURE
-- ============================================================================
-- Place la nourriture sur une case libre.
-- Utilise random + vérification O(1) via bodySet.
-- Fallback sur liste exhaustive si le serpent occupe >70% de la grille (évite boucle infinie).
local function placeFood()
    local attempts = 0
    repeat
        food.x = math.random(cols)
        food.y = math.random(rows)
        attempts = attempts + 1
    until not bodySet[food.x * 1000 + food.y] or attempts > 10

    if attempts > 10 then
        local free = {}
        for x = 1, cols do
            for y = 1, rows do
                if not bodySet[x * 1000 + y] then
                    free[#free + 1] = {x = x, y = y}
                end
            end
        end
        if #free > 0 then
            local chosen = free[math.random(#free)]
            food.x = chosen.x
            food.y = chosen.y
        end
        -- Si free est vide, le serpent remplit toute la grille : victoire implicite
    end
    foodDirty = true
end

-- ============================================================================
-- DESSIN
-- ============================================================================

-- Dessine le serpent entier (utilisé seulement à l'initialisation).
local function drawSnake()
    for _, part in ipairs(snake) do
        drawRect_canvas:fillRect(pixCoord[part.x], pixCoord[part.y], CASE_SIZE, CASE_SIZE, COLOR_SNAKE)
    end
end

-- Dessine la nourriture (appelé uniquement quand foodDirty = true).
local function drawFood()
    drawRect_canvas:fillRect(pixCoord[food.x], pixCoord[food.y], CASE_SIZE, CASE_SIZE, COLOR_FOOD)
end

-- ============================================================================
-- LOGIQUE DE JEU
-- ============================================================================

local function updateSnake()
    -- Calculer la nouvelle position de tête via headCell (table pré-allouée, pas d'alloc GC)
    headCell.x = snake[1].x
    headCell.y = snake[1].y

    if direction == "right" then
        headCell.x = headCell.x + 1
    elseif direction == "left" then
        headCell.x = headCell.x - 1
    elseif direction == "up" then
        headCell.y = headCell.y - 1
    elseif direction == "down" then
        headCell.y = headCell.y + 1
    end

    -- Collision bords
    if headCell.x < 1 or headCell.x > cols or headCell.y < 1 or headCell.y > rows then
        gameOverPending = true
        flashState = 0
        return
    end

    -- Collision corps en O(1) via bodySet
    if bodySet[headCell.x * 1000 + headCell.y] then
        gameOverPending = true
        flashState = 0
        return
    end

    movesSinceFood = movesSinceFood + 1
    local ateFood = (headCell.x == food.x and headCell.y == food.y)

    if ateFood then
        -- Nourriture mangée : le serpent grandit, on alloue une nouvelle tête
        local newHead = {x = headCell.x, y = headCell.y}
        table.insert(snake, 1, newHead)
        bodySet[newHead.x * 1000 + newHead.y] = true
        drawRect_canvas:fillRect(pixCoord[newHead.x], pixCoord[newHead.y], CASE_SIZE, CASE_SIZE, COLOR_SNAKE)

        score = score + math.max(10, 100 - movesSinceFood * 2) + (#snake - 3) * 5
        movesSinceFood = 0
        if score > maxScore then maxScore = score end
        placeFood()
    else
        -- Mouvement normal : on recycle la table de queue comme nouvelle tête (zéro alloc)
        local recycled = table.remove(snake)
        bodySet[recycled.x * 1000 + recycled.y] = nil
        drawRect_canvas:fillRect(pixCoord[recycled.x], pixCoord[recycled.y], CASE_SIZE, CASE_SIZE, COLOR_BACKGROUND)

        recycled.x = headCell.x
        recycled.y = headCell.y
        table.insert(snake, 1, recycled)
        bodySet[recycled.x * 1000 + recycled.y] = true
        drawRect_canvas:fillRect(pixCoord[recycled.x], pixCoord[recycled.y], CASE_SIZE, CASE_SIZE, COLOR_SNAKE)
    end

    -- Mise à jour de la barre de statut uniquement si score ou vitesse ont changé
    local currentChevrons = getSpeedChevrons()
    if score ~= lastDisplayedScore or currentChevrons ~= lastDisplayedSpeed then
        statusBar:setText("Score: " .. score .. " | Max: " .. maxScore .. " | " .. string.rep(">", currentChevrons))
        lastDisplayedScore = score
        lastDisplayedSpeed = currentChevrons
    end
end

-- ============================================================================
-- BOUCLE PRINCIPALE DU JEU
-- ============================================================================
-- Rendu: 50ms fixe (20 FPS)
-- Mouvement: basé sur getSpeed() via time:monotonic()
-- Réactivité: mouvement immédiat si directionChanged = true
-- ============================================================================
local function update()
    -- Animation de mort : clignotement du serpent avant l'écran game over
    if gameOverPending then
        flashState = flashState + 1
        if (flashState - 1) % 4 == 0 then
            local phase = math.floor((flashState - 1) / 4)
            local color = (phase % 2 == 0) and COLOR_BACKGROUND or COLOR_SNAKE
            for _, part in ipairs(snake) do
                drawRect_canvas:fillRect(pixCoord[part.x], pixCoord[part.y], CASE_SIZE, CASE_SIZE, color)
            end
        end
        if flashState >= 24 then
            gameOverTimeout = time:setTimeout(afficheEcranGameOver, 50)
            gameOverPending = false
        end
        return
    end

    local now = time:monotonic()
    local speed = getSpeed()

    if directionChanged or (now - lastMoveTime >= speed) then
        lastMoveTime = now
        directionChanged = false
        updateSnake()
    end

    -- Redessine la nourriture uniquement si elle a changé de position
    if foodDirty then
        drawFood()
        foodDirty = false
    end
end

-- ============================================================================
-- ÉCRAN GAME OVER
-- ============================================================================

afficheEcranGameOver = function()
    cleanupGame()

    local winEcranGameOver = manageWindow()

    local gameoverCanvas = gui:canvas(winEcranGameOver, 0, 0, 320, 480)
    gui:image(gameoverCanvas, "GameOver.png", 0, 0, 320, 480, COLOR_BACKGROUND)

    local scoreFinal = gui:label(winEcranGameOver, 80, 200, 160, 30)
    scoreFinal:setBackgroundColor(COLOR_BACKGROUND)
    scoreFinal:setText("Score: " .. score)
    scoreFinal:setFontSize(20)
    scoreFinal:setTextColor(COLOR_FINAL_SCORE)
    scoreFinal:setHorizontalAlignment(CENTER_ALIGNMENT)
    scoreFinal:setVerticalAlignment(CENTER_ALIGNMENT)

    local bestScore = gui:label(winEcranGameOver, 80, 240, 160, 30)
    bestScore:setBackgroundColor(COLOR_BACKGROUND)
    bestScore:setText("Meilleur: " .. maxScore)
    bestScore:setFontSize(20)
    bestScore:setTextColor(COLOR_FINAL_MAX)
    bestScore:setHorizontalAlignment(CENTER_ALIGNMENT)
    bestScore:setVerticalAlignment(CENTER_ALIGNMENT)

    createButton(winEcranGameOver, 40, 440, 100, 30, t("back"), function() afficheEcranAccueil() end)
    createButton(winEcranGameOver, 180, 440, 100, 30, t("quit"), function() gui:setWindow(nil) end)
end

-- ============================================================================
-- ÉCRAN INSTRUCTIONS
-- ============================================================================

afficheEcranInstructions = function()
    local win = manageWindow()

    local canvas = gui:canvas(win, 0, 0, 320, 480)
    canvas:fillRect(0, 0, 320, 480, COLOR_BACKGROUND)

    local title = gui:label(win, 0, 20, 320, 40)
    title:setFontSize(28)
    title:setText(t("titleInstructions"))
    title:setTextColor(COLOR_YELLOW)
    title:setBackgroundColor(COLOR_BACKGROUND)
    title:setHorizontalAlignment(CENTER_ALIGNMENT)

    local instructions = gui:label(win, 20, 80, 280, 200)
    instructions:setFontSize(18)
    instructions:setText(t("instructionText"))
    instructions:setTextColor(COLOR_WHITE)
    instructions:setBackgroundColor(COLOR_BACKGROUND)
    instructions:setHorizontalAlignment(CENTER_ALIGNMENT)
    instructions:setVerticalAlignment(CENTER_ALIGNMENT)

    createButton(win, 40, 420, 240, 40, t("back"), function() afficheEcranSettings() end)
end

-- ============================================================================
-- ÉCRAN PARAMÈTRES
-- ============================================================================

afficheEcranSettings = function()
    local win = manageWindow()

    local canvas = gui:canvas(win, 0, 0, 320, 480)
    canvas:fillRect(0, 0, 320, 480, COLOR_BACKGROUND)

    local title = gui:label(win, 0, 20, 320, 40)
    title:setFontSize(28)
    title:setText(t("titleSettings"))
    title:setTextColor(COLOR_YELLOW)
    title:setBackgroundColor(COLOR_BACKGROUND)
    title:setHorizontalAlignment(CENTER_ALIGNMENT)

    -- Sélection de la langue
    local langLabel = gui:label(win, 20, 90, 280, 30)
    langLabel:setFontSize(20)
    langLabel:setText(t("language") .. ":")
    langLabel:setTextColor(COLOR_WHITE)
    langLabel:setBackgroundColor(COLOR_BACKGROUND)

    local langFR = gui:label(win, 40, 130, 100, 35)
    langFR:setFontSize(18)
    langFR:setText("Français")
    langFR:setBackgroundColor(prefs.language == "fr" and COLOR_SUCCESS or COLOR_BUTTON)
    langFR:setHorizontalAlignment(CENTER_ALIGNMENT)
    langFR:setVerticalAlignment(CENTER_ALIGNMENT)
    langFR:setBorderSize(1)
    langFR:setRadius(10)
    langFR:onClick(function()
        prefs.language = "fr"
        savePreferences()
        afficheEcranSettings()
    end)

    local langEN = gui:label(win, 180, 130, 100, 35)
    langEN:setFontSize(18)
    langEN:setText("English")
    langEN:setBackgroundColor(prefs.language == "en" and COLOR_SUCCESS or COLOR_BUTTON)
    langEN:setHorizontalAlignment(CENTER_ALIGNMENT)
    langEN:setVerticalAlignment(CENTER_ALIGNMENT)
    langEN:setBorderSize(1)
    langEN:setRadius(10)
    langEN:onClick(function()
        prefs.language = "en"
        savePreferences()
        afficheEcranSettings()
    end)

    -- Sélection de la difficulté
    local diffLabel = gui:label(win, 20, 190, 280, 30)
    diffLabel:setFontSize(20)
    diffLabel:setText(t("difficulty") .. ":")
    diffLabel:setTextColor(COLOR_WHITE)
    diffLabel:setBackgroundColor(COLOR_BACKGROUND)

    local difficulties = {"easy", "medium", "hard"}
    local diffX = {20, 120, 220}

    for i, diff in ipairs(difficulties) do
        local btn = gui:label(win, diffX[i], 230, 80, 35)
        btn:setFontSize(16)
        btn:setText(t(diff))
        btn:setBackgroundColor(prefs.difficulty == diff and difficultyConfig[diff].snakeColor or COLOR_BUTTON)
        btn:setHorizontalAlignment(CENTER_ALIGNMENT)
        btn:setVerticalAlignment(CENTER_ALIGNMENT)
        btn:setBorderSize(1)
        btn:setRadius(10)
        btn:onClick(function()
            prefs.difficulty = diff
            savePreferences()
            afficheEcranSettings()
        end)
    end

    createButton(win, 40, 300, 240, 40, t("instructions"), function() afficheEcranInstructions() end)
    createButton(win, 40, 360, 240, 40, t("back"),         function() afficheEcranAccueil() end)
end

-- ============================================================================
-- ÉCRAN DE JEU
-- ============================================================================

afficheEcranJeu = function()
    -- Annule un timeout game over éventuellement en attente
    if gameOverTimeout then
        time:removeTimeout(gameOverTimeout)
        gameOverTimeout = nil
    end

    local winEcranJeu = manageWindow()
    lastMoveTime = time:monotonic()

    applyDifficulty()

    statusBar = gui:label(winEcranJeu, 0, 0, SCREEN_WIDTH, STATUS_BAR_HEIGHT)
    statusBar:setBackgroundColor(COLOR_BACKGROUND)
    statusBar:setFontSize(20)
    statusBar:setTextColor(COLOR_INGAME_SCORE)
    statusBar:setHorizontalAlignment(CENTER_ALIGNMENT)
    statusBar:setVerticalAlignment(CENTER_ALIGNMENT)
    statusBar:setBorderColor(COLOR_BORDER)
    statusBar:setBorderSize(1)

    -- Initialisation du serpent et du bodySet
    snake = {{x=3, y=2}, {x=2, y=2}, {x=1, y=2}}
    bodySet = {}
    for _, part in ipairs(snake) do
        bodySet[part.x * 1000 + part.y] = true
    end

    -- Position initiale de la nourriture (garantie hors serpent)
    food.x = math.random(cols)
    food.y = math.random(rows)
    while bodySet[food.x * 1000 + food.y] do
        food.x = math.random(cols)
        food.y = math.random(rows)
    end
    foodDirty = true

    direction = "down"
    score = 0
    movesSinceFood = 0
    local initChevrons = getSpeedChevrons()
    statusBar:setText("Score: 0 | Max: " .. maxScore .. " | " .. string.rep(">", initChevrons))
    lastDisplayedScore = 0
    lastDisplayedSpeed = initChevrons
    gameRunning = true

    local canvasW = cols * CELL_SIZE
    local canvasH = rows * CELL_SIZE
    drawRect_canvas = gui:canvas(winEcranJeu, paddingX, STATUS_BAR_HEIGHT + paddingY, canvasW, canvasH)

    -- Contrôles tactiles : direction selon position du touch par rapport au centre du canvas
    drawRect_canvas:onTouch(function(a)
        local diffX = a[1] - canvasW / 2
        local diffY = a[2] - canvasH / 2

        local newDirection = direction

        if math.abs(diffX) > math.abs(diffY) then
            if diffX > 0 and direction ~= "left" then
                newDirection = "right"
            elseif diffX < 0 and direction ~= "right" then
                newDirection = "left"
            end
        else
            if diffY < 0 and direction ~= "down" then
                newDirection = "up"
            elseif diffY > 0 and direction ~= "up" then
                newDirection = "down"
            end
        end

        if newDirection ~= direction then
            direction = newDirection
            directionChanged = true
        end
    end)

    -- Fond et bordures de la zone de jeu
    drawRect_canvas:fillRect(0, 0, canvasW, canvasH, COLOR_BACKGROUND)
    drawRect_canvas:fillRect(0, 0, canvasW, 1, COLOR_BORDER)
    drawRect_canvas:fillRect(0, canvasH - 1, canvasW, 1, COLOR_BORDER)
    drawRect_canvas:fillRect(0, 0, 1, canvasH, COLOR_BORDER)
    drawRect_canvas:fillRect(canvasW - 1, 0, 1, canvasH, COLOR_BORDER)

    drawSnake()
    drawFood()
    foodDirty = false

    rythme = time:setInterval(update, 50)
end

-- ============================================================================
-- ÉCRAN D'ACCUEIL
-- ============================================================================

afficheEcranAccueil = function()
    cleanupGame()

    local winEcranAccueil = manageWindow()

    local accueilCanvas = gui:canvas(winEcranAccueil, 0, 0, 320, 480)
    gui:image(accueilCanvas, "PaxoSnake.png", 0, 0, 320, 480, COLOR_BACKGROUND)

    createButton(winEcranAccueil, 10,  440, 95, 30, t("play"),     function() afficheEcranJeu() end)
    createButton(winEcranAccueil, 112, 440, 95, 30, t("settings"), function() afficheEcranSettings() end)
    createButton(winEcranAccueil, 215, 440, 95, 30, t("quit"),     function() gui:setWindow(nil) end)
end

-- ============================================================================
-- POINTS D'ENTRÉE (globaux : exigés par le runtime PaxOS)
-- ============================================================================

function run()
    loadPreferences()
    afficheEcranAccueil()
end

function quit()
    return
end
