-- ============================================================================
--                              SNAKE - PAXOPHONE
-- ============================================================================
-- Jeu du Snake adapté pour le Paxophone
--
-- Commandes tactiles : Toucher l'écran par rapport au centre pour choisir
-- la direction (haut/bas/gauche/droite)
--
-- Score :
--   - -1 point par mouvement
--   - +35 points de base par nourriture mangée
--   - Bonus de +5 points par segment supplémentaire du serpent
--   - Le score ne peut pas être négatif
--
-- Vitesse :
--   - Commence à 400ms, diminue de 10ms par segment
--   - Plafond à 100ms
--   - Affichée via des chevrons (1 à 5)
-- ============================================================================

local direction = "down"
local oldWin
local rythme
local gameRunning = false
local gameOverTimeout  -- Permet de différer l'appel à afficheEcranGameOver

function int(x)
    return math.floor(x)
end

-- ============================================================================
-- CONFIGURATION DE L'ÉCRAN
-- ============================================================================
-- Dimensions des cases de la grille
local CELL_SIZE = 20        -- Taille totale d'une case (case + espacement)
local GAP = 2                -- Espace entre deux cases
local CASE_SIZE = CELL_SIZE - GAP  -- Taille visuelle de la case

-- Dimensions de la barre de statut (en pixels)
local STATUS_BAR_HEIGHT = 40
local SCREEN_WIDTH = 320
local SCREEN_HEIGHT = 480

-- ============================================================================
-- COULEURS DU JEU
-- ============================================================================
-- Toutes les couleurs utilisées dans le jeu pour une modification centralisée
local COLOR_BORDER = COLOR_YELLOW     -- Bordures (zone de jeu + barre de statut)
local COLOR_BACKGROUND = COLOR_DARK    -- Fond de la zone de jeu
local COLOR_SNAKE = COLOR_GREEN       -- Corps du serpent
local COLOR_FOOD = COLOR_RED           -- Nourriture
local COLOR_INGAME_SCORE = COLOR_GREEN -- Texte du score en jeu
local COLOR_FINAL_SCORE = COLOR_GREEN  -- Texte du score en écran game over
local COLOR_FINAL_MAX = COLOR_YELLOW   -- Texte du meilleur score
local COLOR_BUTTON = COLOR_LIGHT_GREY  -- Boutons

-- ============================================================================
-- CALCUL DE LA GRILLE
-- ============================================================================
-- La grille est calculée automatiquement pour remplir la zone de jeu
-- en fonction de la taille des cases

local GAME_W = SCREEN_WIDTH
local GAME_H = SCREEN_HEIGHT - STATUS_BAR_HEIGHT

local cols = math.floor(GAME_W / CELL_SIZE)    -- Nombre de colonnes (16)
local rows = math.floor(GAME_H / CELL_SIZE)   -- Nombre de lignes (22)
local paddingX = math.floor((GAME_W - cols * CELL_SIZE) / 2)  -- Marge X (0)
local paddingY = math.floor((GAME_H - rows * CELL_SIZE) / 2)  -- Marge Y (0)

local gridSize = {w = cols, h = rows}  -- Dimensions de la grille de jeu

-- ============================================================================
-- SYSTÈME DE SCORE
-- ============================================================================
local score = 0          -- Score actuel de la partie en cours
local maxScore = 0       -- Meilleur score atteint depuis l'installation
-- Points gagnés par nourriture : (nb cases écran) / 10 = 35 points
local FOOD_POINTS = math.floor(cols * rows / 10)

-- ============================================================================
-- SYSTÈME DE VITESSE
-- ============================================================================
-- Le serpent accélère à mesure qu'il grandit
-- Formule : vitesse = GAME_SPEED - (longueur_serpent * SPEED_DECREASE)
local GAME_SPEED = 400     -- Vitesse initiale en ms (lent)
local SPEED_DECREASE = 10 -- Millisecondes retirées par segment
local MIN_SPEED = 100     -- Vitesse minimum absolue (très rapide)

-- Retourne la vitesse actuelle en millisecondes
local function getSpeed()
    if not snake or #snake == 0 then
        return GAME_SPEED
    end
    local speed = GAME_SPEED - (#snake * SPEED_DECREASE)
    return math.max(speed, MIN_SPEED)
end

-- Retourne le nombre de chevrons (1-5) selon la vitesse
-- Échelle : 400ms = 1 chevron, 340ms = 2, 280ms = 3, 220ms = 4, 160ms = 5
local function getSpeedChevrons()
    local speed = getSpeed()
    local diff = GAME_SPEED - speed
    local chevrons = math.floor(diff / 60) + 1
    return math.min(chevrons, 5)
end

-- Retourne la chaîne de chevrons pour l'affichage (ex: ">>>")
local function getSpeedString()
    local count = getSpeedChevrons()
    return string.rep(">", count)
end

local food = {x=math.random(gridSize.w), y=math.random(gridSize.h)}

-- Fonction de création d'une fenetre
-- si oldWin existe, alors on delete oldWin
-- oldWin existe si ce n'est pas la première fenetre créée
function manageWindow()

    local win = gui:window()
    gui:setWindow(win)
    if oldWin then 
        gui:del(oldWin) 
        oldWin = nil 
    end
    oldWin = win
    return win

end

-- ------------------------------------------------
--        GESTION DE L'ECRAN D'ACCUEIL 
-- ------------------------------------------------

-- Initialise l'écran d'accueil
function afficheEcranAccueil()
    print("dbg-afficheEcranAccueil")
    
    -- Nettoyage : arrêter le timer de jeu et annuler le timeout game over
    if rythme then
        time:removeInterval(rythme)
        rythme = nil
    end
    if gameOverTimeout then
        time:removeTimeout(gameOverTimeout)
        gameOverTimeout = nil
    end
    gameRunning = false
    
    local winEcranAccueil = manageWindow()

    local accueilCanvas = gui:canvas(winEcranAccueil, 0, 0, 320, 480)
    local imageAccueil = gui:image(accueilCanvas, "PaxoSnake.png", 0, 0, 320, 480, COLOR_BACKGROUND)

    -- local lblTitle = gui:label(winEcranAccueil, 15, 10, 200, 28)
    -- lblTitle:setFontSize(24)
    -- lblTitle:setText("Snake")

    local lblPlay = gui:label(winEcranAccueil, 40, 440, 100, 30)
    lblPlay:setFontSize(20)
    lblPlay:setHorizontalAlignment(CENTER_ALIGNMENT)
    lblPlay:setVerticalAlignment(CENTER_ALIGNMENT)
    lblPlay:setBorderSize(1)
    lblPlay:setRadius(10)
    lblPlay:setBackgroundColor(COLOR_BUTTON)
    lblPlay:setText("Jouer")
    lblPlay:onClick(function() afficheEcranJeu(); end)

    local lblQuit = gui:label(winEcranAccueil, 180, 440, 100, 30)
    lblQuit:setFontSize(20)
    lblQuit:setHorizontalAlignment(CENTER_ALIGNMENT)
    lblQuit:setVerticalAlignment(CENTER_ALIGNMENT)
    lblQuit:setBorderSize(1)
    lblQuit:setRadius(10)
    lblQuit:setBackgroundColor(COLOR_BUTTON)
    lblQuit:setText("Quitter")
    lblQuit:onClick(function() gui:setWindow(nil); end)
    print("dbg-finEcranAccueil")

end

-- ------------------------------------------------
--        GESTION DE L'ECRAN GAME OVER 
-- ------------------------------------------------

-- Initialise l'écran Game Over
function afficheEcranGameOver()
    print("dbg-afficheEcranGameOver")

    gameRunning = false
    -- Arrête le timer AVANT manageWindow() pour éviter tout conflit
    if rythme then
        time:removeInterval(rythme)
        rythme = nil
    end
    
    local winEcranGameOver = manageWindow()

    local gameoverCanvas = gui:canvas(winEcranGameOver, 0, 0, 320, 480)
    local imageGameover = gui:image(gameoverCanvas, "GameOver.png", 0, 0, 320, 480, COLOR_BACKGROUND)

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

    -- local lblTitle = gui:label(winEcranGameOver, 15, 10, 200, 28)
    -- lblTitle:setFontSize(24)
    -- lblTitle:setText("Game Over")

    local lblAccueil = gui:label(winEcranGameOver, 40, 440, 100, 30)
    lblAccueil:setFontSize(20)
    lblAccueil:setHorizontalAlignment(CENTER_ALIGNMENT)
    lblAccueil:setVerticalAlignment(CENTER_ALIGNMENT)
    lblAccueil:setBorderSize(1)
    lblAccueil:setRadius(10)
    lblAccueil:setBackgroundColor(COLOR_BUTTON)
    lblAccueil:setText("Accueil")
    lblAccueil:onClick(function() afficheEcranAccueil() end)

    local lblQuit = gui:label(winEcranGameOver, 180, 440, 100, 30)
    lblQuit:setFontSize(20)
    lblQuit:setHorizontalAlignment(CENTER_ALIGNMENT)
    lblQuit:setVerticalAlignment(CENTER_ALIGNMENT)
    lblQuit:setBorderSize(1)
    lblQuit:setRadius(10)
    lblQuit:setBackgroundColor(COLOR_BUTTON)
    lblQuit:setText("Quitter")
    lblQuit:onClick(function() gui:setWindow(nil); end)
    print("dbg-finEcranGameOver")

end

-- ------------------------------------------------
--        GESTION DE L'ECRAN DE JEU
-- ------------------------------------------------

-- Initialise l'écran de jeu
function afficheEcranJeu()
    print("dbg-afficheEcranJeu")
    
    -- Annule un timeout game over en attente (si on revient au jeu depuis l'accueil)
    if gameOverTimeout then
        time:removeTimeout(gameOverTimeout)
        gameOverTimeout = nil
    end
    
    local winEcranJeu = manageWindow()

    statusBar = gui:label(winEcranJeu, 0, 0, SCREEN_WIDTH, STATUS_BAR_HEIGHT)
    statusBar:setBackgroundColor(COLOR_BACKGROUND)
    statusBar:setFontSize(20)
    statusBar:setTextColor(COLOR_INGAME_SCORE)
    statusBar:setHorizontalAlignment(CENTER_ALIGNMENT)
    statusBar:setVerticalAlignment(CENTER_ALIGNMENT)
    statusBar:setBorderColor(COLOR_BORDER)
    statusBar:setBorderSize(1)

    -- Initialisation du serpent : position de départ (x=3, y=2), direction vers le bas, score à 0
    snake = {{x=3, y=2}, {x=2, y=2}, {x=1, y=2}}
    food = {x=math.random(gridSize.w), y=math.random(gridSize.h)}
    direction = "down"
    score = 0
    statusBar:setText("Score: 0 | Max: 0 | " .. getSpeedString())
    gameRunning = true

    local canvasW = cols * CELL_SIZE
    local canvasH = rows * CELL_SIZE
    drawRect_canvas = gui:canvas(winEcranJeu, paddingX, STATUS_BAR_HEIGHT + paddingY, canvasW, canvasH)

    -- ============================================================================
    -- CONTRÔLES TACTILES
    -- ============================================================================
    -- La direction est choisie selon la position du touch par rapport au centre
    -- Si touch à droite du centre → aller à droite
    -- Si touch à gauche du centre → aller à gauche
    -- Si touch en haut du centre → aller en haut
    -- Si touch en bas du centre → aller en bas
    drawRect_canvas:onTouch(function(a)
        local touchX = a[1]
        local touchY = a[2]
        
        local centerX = canvasW / 2
        local centerY = canvasH / 2
        
        local diffX = touchX - centerX
        local diffY = touchY - centerY
        
        if math.abs(diffX) > math.abs(diffY) then
            if diffX > 0 and direction ~= "left" then
                direction = "right"
            elseif diffX < 0 and direction ~= "right" then
                direction = "left"
            end
        else
            if diffY < 0 and direction ~= "down" then
                direction = "up"
            elseif diffY > 0 and direction ~= "up" then
                direction = "down"
            end
        end
    end)

    -- Dessin du fond de la zone de jeu
    drawRect_canvas:fillRect(0, 0, canvasW, canvasH, COLOR_BACKGROUND)

    -- Dessin des bordures autour de la zone de jeu (haut, bas, gauche, droite)
    drawRect_canvas:fillRect(0, 0, canvasW, 1, COLOR_BORDER)
    drawRect_canvas:fillRect(0, canvasH - 1, canvasW, 1, COLOR_BORDER)
    drawRect_canvas:fillRect(0, 0, 1, canvasH, COLOR_BORDER)
    drawRect_canvas:fillRect(canvasW - 1, 0, 1, canvasH, COLOR_BORDER)

    drawSnake()
    drawFood()

    rythme = time:setInterval(update, getSpeed())

end

-- Dessin du serpent : +1 pixel pour décaler les cases et éviter de recouvrir les bordures
function drawSnake()
    for i, part in ipairs(snake) do
        local px = (part.x - 1) * CELL_SIZE + 1
        local py = (part.y - 1) * CELL_SIZE + 1
        drawRect_canvas:fillRect(math.floor(px), math.floor(py), CASE_SIZE, CASE_SIZE, COLOR_SNAKE)
    end
end

-- Dessin de la nourriture : même décalage de +1 pixel
function drawFood()
    local px = (food.x - 1) * CELL_SIZE + 1
    local py = (food.y - 1) * CELL_SIZE + 1
    drawRect_canvas:fillRect(math.floor(px), math.floor(py), CASE_SIZE, CASE_SIZE, COLOR_FOOD)
end

function updateSnake()
    -- Pénalité : -1 point par mouvement (incite à être efficace)
    score = math.max(0, score - 1)
    statusBar:setText("Score: " .. score .. " | Max: " .. maxScore .. " | " .. getSpeedString())
    local head = {x=snake[1].x, y=snake[1].y}

    if direction == "right" then
        head.x = head.x + 1
    elseif direction == "left" then
        head.x = head.x - 1
    elseif direction == "up" then
        head.y = head.y - 1
    elseif direction == "down" then
        head.y = head.y + 1
    end
    -- Vérifier les collisions avec les bords
    
    if head.x < 1 or head.x > gridSize.w or head.y < 1 or head.y > gridSize.h then
        -- Diffère l'appel pour permettre au callback update() de terminer, afin d'évite un conflit avec manageWindow() qui supprime la fenêtre de jeu
        gameOverTimeout = time:setTimeout(afficheEcranGameOver, 50)
        return
    end

    -- Vérifier les collisions avec le corps du serpent
    for i = 2, #snake do
        if head.x == snake[i].x and head.y == snake[i].y then
            gameOverTimeout = time:setTimeout(afficheEcranGameOver, 50)
            return
        end
    end

    table.insert(snake, 1, head)

    if snake[1].x == food.x and snake[1].y == food.y then
        -- Bonus progressif : +5 points par segment au-delà des 3 premiers
        score = score + FOOD_POINTS + (#snake - 3) * 5
        if score > maxScore then maxScore = score end
        statusBar:setText("Score: " .. score .. " | Max: " .. maxScore .. " | " .. getSpeedString())
        -- Mise à jour de la vitesse quand le serpent mange
        time:removeInterval(rythme)
        rythme = time:setInterval(update, getSpeed())
        -- Générer une nouvelle position pour la nourriture
        -- qui n'est pas sur le serpent
        repeat
            food = {x=math.random(gridSize.w), y=math.random(gridSize.h)}
        until not isFoodOnSnake(food)
    else
        local tail = table.remove(snake)
        local px = (tail.x - 1) * CELL_SIZE + 1
        local py = (tail.y - 1) * CELL_SIZE + 1
        drawRect_canvas:fillRect(math.floor(px), math.floor(py), CASE_SIZE, CASE_SIZE, COLOR_BACKGROUND)
    end

    -- Afficher que la tête
    local px = (head.x - 1) * CELL_SIZE + 1
    local py = (head.y - 1) * CELL_SIZE + 1
    drawRect_canvas:fillRect(math.floor(px), math.floor(py), CASE_SIZE, CASE_SIZE, COLOR_SNAKE)
end

function isFoodOnSnake(food)
    for i, part in ipairs(snake) do
        if food.x == part.x and food.y == part.y then
            return true
        end
    end
    return false
end

function update()
    updateSnake()
    drawFood()
end

-- Point d'entrée du programme
function run()
    
    afficheEcranAccueil()
 
end

-- Point de sortie du programme
function quit()
    print("Byebye")
    return
end