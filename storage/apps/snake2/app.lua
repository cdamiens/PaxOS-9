local direction = "down"
local oldWin
local rythme
local gameRunning = false
local gameOverTimeout  -- Permet de différer l'appel à afficheEcranGameOver

function int(x)
    return math.floor(x)
end

local CELL_SIZE = 20
local GAP = 2
local CASE_SIZE = CELL_SIZE - GAP

local STATUS_BAR_HEIGHT = 40
local SCREEN_WIDTH = 320
local SCREEN_HEIGHT = 480

local GAME_W = SCREEN_WIDTH
local GAME_H = SCREEN_HEIGHT - STATUS_BAR_HEIGHT

local cols = math.floor(GAME_W / CELL_SIZE)
local rows = math.floor(GAME_H / CELL_SIZE)
local paddingX = math.floor((GAME_W - cols * CELL_SIZE) / 2)
local paddingY = math.floor((GAME_H - rows * CELL_SIZE) / 2)

local gridSize = {w = cols, h = rows}

local snake = {{x=3, y=2}, {x=2, y=2}, {x=1, y=2}}
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
    local imageAccueil = gui:image(accueilCanvas, "PaxoSnake.png", 0, 0, 320, 480, COLOR_DARK)

    -- local lblTitle = gui:label(winEcranAccueil, 15, 10, 200, 28)
    -- lblTitle:setFontSize(24)
    -- lblTitle:setText("Snake")

    local lblPlay = gui:label(winEcranAccueil, 40, 440, 100, 30)
    lblPlay:setFontSize(20)
    lblPlay:setHorizontalAlignment(CENTER_ALIGNMENT)
    lblPlay:setVerticalAlignment(CENTER_ALIGNMENT)
    lblPlay:setBorderSize(1)
    lblPlay:setRadius(10)
    lblPlay:setBackgroundColor(COLOR_LIGHT_GREY)
    lblPlay:setText("Jouer")
    lblPlay:onClick(function() afficheEcranJeu(); end)

    local lblQuit = gui:label(winEcranAccueil, 180, 440, 100, 30)
    lblQuit:setFontSize(20)
    lblQuit:setHorizontalAlignment(CENTER_ALIGNMENT)
    lblQuit:setVerticalAlignment(CENTER_ALIGNMENT)
    lblQuit:setBorderSize(1)
    lblQuit:setRadius(10)
    lblQuit:setBackgroundColor(COLOR_LIGHT_GREY)
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
    local imageGameover = gui:image(gameoverCanvas, "GameOver.png", 0, 0, 320, 480, COLOR_DARK)

    -- local lblTitle = gui:label(winEcranGameOver, 15, 10, 200, 28)
    -- lblTitle:setFontSize(24)
    -- lblTitle:setText("Game Over")

    local lblAccueil = gui:label(winEcranGameOver, 40, 440, 100, 30)
    lblAccueil:setFontSize(20)
    lblAccueil:setHorizontalAlignment(CENTER_ALIGNMENT)
    lblAccueil:setVerticalAlignment(CENTER_ALIGNMENT)
    lblAccueil:setBorderSize(1)
    lblAccueil:setRadius(10)
    lblAccueil:setBackgroundColor(COLOR_LIGHT_GREY)
    lblAccueil:setText("Accueil")
    lblAccueil:onClick(function() afficheEcranAccueil() end)

    local lblQuit = gui:label(winEcranGameOver, 180, 440, 100, 30)
    lblQuit:setFontSize(20)
    lblQuit:setHorizontalAlignment(CENTER_ALIGNMENT)
    lblQuit:setVerticalAlignment(CENTER_ALIGNMENT)
    lblQuit:setBorderSize(1)
    lblQuit:setRadius(10)
    lblQuit:setBackgroundColor(COLOR_LIGHT_GREY)
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

    local statusBar = gui:label(winEcranJeu, 0, 0, SCREEN_WIDTH, STATUS_BAR_HEIGHT)
    statusBar:setBackgroundColor(COLOR_DARK)
    statusBar:setText("Score: 0")
    statusBar:setFontSize(20)
    statusBar:setTextColor(COLOR_GREEN)
    statusBar:setHorizontalAlignment(CENTER_ALIGNMENT)
    statusBar:setVerticalAlignment(CENTER_ALIGNMENT)

    snake = {{x=3, y=2}, {x=2, y=2}, {x=1, y=2}}
    food = {x=math.random(gridSize.w), y=math.random(gridSize.h)}
    direction = "down"
    gameRunning = true

    local canvasW = cols * CELL_SIZE
    local canvasH = rows * CELL_SIZE
    drawRect_canvas = gui:canvas(winEcranJeu, paddingX, STATUS_BAR_HEIGHT + paddingY, canvasW, canvasH)

    drawRect_canvas:onTouch(function(a)
        local px = (snake[1].x - 1) * CELL_SIZE
        local py = (snake[1].y - 1) * CELL_SIZE
        local diff = {x=px - a[1], y=py - a[2]}
        print(diff.x)
        print(diff.y)
        if (math.abs(diff.x) > math.abs(diff.y)) then
            if(direction ~= "right" and direction ~= "left") then
                if(diff.x < 0) then
                    direction = "right"
                else
                    direction = "left"
                end
            end
        else
            if(direction ~= "down" and direction ~= "up") then
                if(diff.y < 0) then
                    direction = "down"
                else
                    direction = "up"
                end
            end
        end
        print(direction)
    end)

    drawRect_canvas:fillRect(0, 0, canvasW, canvasH, COLOR_DARK)
    drawSnake()
    drawFood()

    rythme = time:setInterval(update, 300)

end

function drawSnake()
    for i, part in ipairs(snake) do
        local px = (part.x - 1) * CELL_SIZE
        local py = (part.y - 1) * CELL_SIZE
        drawRect_canvas:fillRect(math.floor(px), math.floor(py), CASE_SIZE, CASE_SIZE, COLOR_GREEN)
    end
end

function drawFood()
    local px = (food.x - 1) * CELL_SIZE
    local py = (food.y - 1) * CELL_SIZE
    drawRect_canvas:fillRect(math.floor(px), math.floor(py), CASE_SIZE, CASE_SIZE, COLOR_RED)
end

function updateSnake()
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
        -- Générer une nouvelle position pour la nourriture
        -- qui n'est pas sur le serpent
        repeat
            food = {x=math.random(gridSize.w), y=math.random(gridSize.h)}
        until not isFoodOnSnake(food)
    else
        local tail = table.remove(snake)
        local px = (tail.x - 1) * CELL_SIZE
        local py = (tail.y - 1) * CELL_SIZE
        drawRect_canvas:fillRect(math.floor(px), math.floor(py), CASE_SIZE, CASE_SIZE, COLOR_DARK)
    end

    -- Afficher que la tête
    local px = (head.x - 1) * CELL_SIZE
    local py = (head.y - 1) * CELL_SIZE
    drawRect_canvas:fillRect(math.floor(px), math.floor(py), CASE_SIZE, CASE_SIZE, COLOR_GREEN)
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