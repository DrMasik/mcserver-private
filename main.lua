-------------------------------------------------------------------------------

PLUGIN = nil -- Plugin object handler
MsgSuffix = "Private: "

private_db = nil      -- SQLite file object handler for in disk private area data
-- g_private_db_tmp = nil  -- SQLite in memory copy of in disk private area data (speed up)

g_tmp_db  = nil -- SQLite in memmory temp database

g_player_data = nil -- In memory player database

g_area_size_min = 16 -- Minimun area size. Read from config
g_area_size_max = 500 -- Maximum area size. Read from config

g_DEFAULT_MAX_AREA_COUNT = 1  -- Like Constans for default config
g_MAX_TOTAL_AREA_SIZE = 500   -- Like Constant for default config


g_MAX_Y = 255
g_MIN_Y = 0

-------------------------------------------------------------------------------

function Initialize(Plugin)
  Plugin:SetName("Private")
  Plugin:SetVersion(0)

  PLUGIN = Plugin

  LOG(MsgSuffix .. Plugin:GetName() .. " initialize...")

  -- Setup hooks
  cPluginManager.AddHook(cPluginManager.HOOK_PLAYER_LEFT_CLICK, MyOnPlayerLeftClick)
  cPluginManager.AddHook(cPluginManager.HOOK_PLAYER_RIGHT_CLICK, MyOnPlayerRightClick)

  -- Load the InfoReg shared library:
  dofile(cPluginManager:GetPluginsPath() .. "/InfoReg.lua")

  -- Bind all the console commands:
  RegisterPluginInfoConsoleCommands()

  -- Bind all the commands (userspace):
  RegisterPluginInfoCommands()

  -- Create or open database
  LOG(MsgSuffix .. "Open database private.sqlite3...")
  private_db = sqlite3.open(PLUGIN:GetLocalFolder() .. "/private.sqlite3")

  LOG(MsgSuffix .. "Create database if not exists")
  create_database()

  -- Create in memory database for player data save
  LOG(MsgSuffix .. "Create in-memory temp database")

  if not create_temp_db() then
    LOG(MsgSuffix .. ">> Can\'t create temp database")
    return false
  end

  -- Create in-memory private database
  -- Future request
  -- LGO(MsgSuffix .."Create in-memmory private temp database")
  -- if not private_db_tmp_create() then
  --   LOG(MsgSuffix .. ">> Can\'t create in-memory private temp database")
  --   return false
  -- end

  -- Nice message :)
  LOG(MsgSuffix .. "Initialized " .. Plugin:GetName() .. " v." .. Plugin:GetVersion())

  return true
end

-------------------------------------------------------------------------------

function create_temp_db()
-- Create in memmory database for temporary data holding and manipulation

  g_tmp_db = sqlite3.open_memory()

  if not g_tmp_db then
    return false
  end

  --
  -- Create tables
  --

  local sql = [=[
    CREATE TABLE IF NOT EXISTS data(
      world text, uuid text, mark integer,
      x1 integer, y1 integer, z1 integer,
      x2 integer, y2 integer, z2 integer,
      x01 integer, y01 integer, z01 integer,
      x02 integer, y02 integer, z02 integer,
      x03 integer, y03 integer, z03 integer,
      x04 integer, y04 integer, z04 integer);

    CREATE INDEX IF NOT EXISTS data_world_uuid on data(world, uuid);
    CREATE INDEX IF NOT EXISTS data_world_uuid_mark on data(world, uuid, mark);
  ]=]

  -- Execute SQL statement
  if g_tmp_db:exec(sql) ~= sqlite3.OK then
    console_log("Can\'t create tables into in memory DB")
    return false
  end

  return true
end

-------------------------------------------------------------------------------

function create_database()
-- Create DB if not exists

  local sql =[=[
    CREATE TABLE IF NOT EXISTS area(
      world text, uuid text,
      x1 integer, y1 integer, z1 integer,
      x2 integer, y2 integer, z2 integer,
      x3 integer, y3 integer, z3 integer,
      x4 integer, y4 integer, z4 integer,
      area_size integer, area_name text
    );

    CREATE TABLE IF NOT EXISTS config(
      world text, uuid text,
      areas_count integer,
      areas_total_size integer
    );

    CREATE INDEX IF NOT EXISTS config_world_uuid on config(world, uuid);

  ]=]

  if private_db:exec(sql) ~= sqlite3.OK then
    console_log("Error. create_database() -> private_db:exec(sql)")
    return false
  end

  -- Write down defaul data into config table
  create_default_config()

  return true
end

-------------------------------------------------------------------------------

function CommandMark(Split, Player)
-- Begin mark square.

  if not Player then
    return false
  end

  local ret = nil

  -- Check number of available areas
  -- if available_area_count() < 1 then
  --    Player:SendMessage("You do not have more free areas.")
  --    return true
  -- end

  -- Check available area size
  -- if available_area_size() < g_area_size_min then
  --   Player:SendMessage("You do not have free area")
  --   return true
  -- end

  --
  -- Does we have the record (player run command some time)
  --
  if is_mark_exists(Player) then
    Player:SendMessageInfo("Marker already activated")
    return true
  end

  -- All right - create record in temp DB
  -- g_tmp_db:exec()
  local stmt = g_tmp_db:prepare("INSERT INTO data(world, uuid, mark) VALUES(?, ?, ?);")

  if not stmt then
    Player:SendMessage("Some error. Can\'t mark area. Talk admin")
    console_log("Can\'t prepare SQL statement to create marked record")
    return true
  end

  --
  -- Bind values for SQL statements
  --
  if stmt:bind(1, Player:GetWorld():GetName()) ~= sqlite3.OK then
    Player:SendMessage("Some error. Can\'t mark area. Talk admin")
    console_log("Can\'t bind value #1 for SQL statement to create marked record")
    return true
  end

  if stmt:bind(2, Player:GetUUID()) ~= sqlite3.OK then
    Player:SendMessage("Some error. Can\'t mark area. Talk admin")
    console_log("Can\'t bind value #2 for SQL statement to create marked record")
    return true
  end

  if stmt:bind(3, 1) ~= sqlite3.OK then
    Player:SendMessage("Some error. Can\'t mark area. Talk admin")
    console_log("Can\'t bind value #3 for SQL statement to create marked record")
    return true
  end

  --
  -- Try to execute SQL statement
  --

  ret = stmt:step()

  if ret ~= sqlite3.DONE then
    Player:SendMessage("Some error. Can\'t mark area. Talk admin")
    console_log("Can\'t execute stmt:step() for SQL statement to create marked record. Error code: " .. ret)
    return true
  end

  if stmt:finalize() ~= sqlite3.OK then  -- Finish him!
    Player:SendMessage("Some error. Can\'t mark area. Talk admin")
    console_log("Can\'t stmt:finalize() for SQL statement to create marked record")
    return true
  end

  -- Talk with player
  Player:SendMessageSuccess("Private marker activated")

  return true
end

-------------------------------------------------------------------------------

function CommandCancel(Split, Player)
-- Cancel mark operation

  if not Player then
    return false
  end

  if not clean_player_data(Player) then
    player_message_error(Player, "Some error on canceled oparation")
  else
    Player:SendMessageSuccess("Private marker canceled")
  end

  return true
end -- CommandCancel

-------------------------------------------------------------------------------

function CommandSave(Split, Player)
-- Save merked square

  if not Player then
    console_log("Error. CommandSave() -> Player is nil")
    return false
  end

  -- Is it coordinates set and mark activated
  if not is_area_selected(Player) then
    player_message_error(Player, "Area not selected")
    return true
  end

  -- Get player config
  local player_area_max_count, player_area_max_size = player_get_config(Player)

  -- Calculate area size
  local area_size = area_size_calculate(Player)

  if not area_size then
    console_log("Error. CommandSave() -> area_size_calculate(Player)")
    player_message_error(Player)
    return false
  end

  -- Check minimum area size
  if area_size < g_area_size_min then
    player_message_error(Player, "Area too small. Minimum area size is ".. g_area_size_min ..", your area size is ".. area_size)
    return true
  end

  -- Check maximum area size
  if area_size > player_area_max_size then
    player_message_error(Player, "Area too big. Maximum area size is ".. player_area_max_size ..". Your area size is ".. area_size)
    return true
  end

  -- Check player area count
  if player_areas_count(Player) >= player_area_max_count then
    player_message_error(Player, "No more free areas for you")
    return true
  end

  -- Calculate area corners
  if not area_corners_calculate(Player) then
    console_log("Error. area_corners_calculate return false")
    player_message_error(Player)
    return true
  end

  -- Check is it area has owner
  local owner_exists = is_area_has_owner(Player)

  if owner_exists == 1 then
    player_message_error(Player, "Area has owner. Select another region")

    -- Delete user data
    --   player_clean_data(Player)

    return true
  elseif owner_exists < 0 then  -- Some error in function
    player_message_error(Player)
    return true
  end

  -- Get the area name
  local area_name = tostring(Split[3] or math.random(1, 100))

  -- All right. Try to save data
  if not player_save_area(Player, area_name) then
    player_message_error(Player)
    return true
  end

  -- Talk with player
  Player:SendMessageSuccess("Area saved as ".. area_name ..", area size is ".. area_size)

  -- Clean marker
  clean_player_data(Player)

  return true
end -- CommandSave

-------------------------------------------------------------------------------

function on_player_click(Player, BlockX, BlockY, BlockZ, BlockFace, Action, ClickedButton)
-- ClickedButton - 1 -left click, 2 - right click

  -- Is it Player object exists. If not - go away
  if not Player then
    player_message_error(Player)
    console_log("Error. on_player_click() -> empty Player")
    return false
  end

  -- Button was clicked
  if ClickedButton ~= 1 and ClickedButton ~= 2 then
    player_message_error(Player)
    console_log("Error. on_player_click() -> Unknown ClickedButton = ".. ClickedButton)
    return false
  end

  -- Check is it area (corner) beasy (other owner)

  -- Check, is it marked action
  -- if not is_mark_exists(Player) then
  --   return true
  -- end

  -- All right - save point
  if not save_corner_position(Player, ClickedButton, math.floor(BlockX), math.floor(BlockY), math.floor(BlockZ)) then
    return false
  end

  -- Show user information
  Player:SendMessageSuccess("Point coordinates is (".. math.floor(BlockX) ..", ".. math.floor(BlockY) ..", ".. math.floor(BlockZ) ..")")

  -- Inform player for next step
  Player:SendMessageSuccess("Click another button for second point or \"/private save\" to save private area")

  return true
end -- on_player_click

-------------------------------------------------------------------------------

function MyOnPlayerLeftClick(Player, BlockX, BlockY, BlockZ, BlockFace, Action)

  -- Is it try to create area?
  if not is_mark_exists(Player) then
    if check_block_access(Player, BlockX, BlockY, BlockZ) == 0 then  -- 1 - player has access, 0 - no access
      return true
    end

    return false
  end

  if not on_player_click(Player, BlockX, BlockY, BlockZ, BlockFace, Action, 1) then
    player_message_error(Player)
    console_log("Error. MyOnPlayerLeftClick()")
  else
    return true
  end

  -- Do not block access to object
  return false

end

-------------------------------------------------------------------------------

function MyOnPlayerRightClick(Player, BlockX, BlockY, BlockZ, BlockFace, Action)

  if not is_mark_exists(Player) then
    if check_block_access(Player, BlockX, BlockY, BlockZ) == 0 then  -- 1 - player has access, 0 - no access
      return true
    end

    return false
  end

  if not on_player_click(Player, BlockX, BlockY, BlockZ, BlockFace, Action, 2) then
    player_message_error(Player)
    console_log("Error. MyOnPlayerRightClick()")
  else
    return true
  end

  return false
end

-------------------------------------------------------------------------------

function area_size_calculate(Player)
-- Calculate area size
-- Cordinates may be <0 and >0.

  local x1, z1, x2, z2 = area_corners_2v(Player)

  -- calculate square border lingth
  local x_length = 0
  local z_length = 0

  x_length = distance_2v(x1, x2)

  if not x_length then
    console_log("Error. area_size_calculate() -> x_length")
    return false
  end

  z_length = distance_2v(z1, z2)

  if not z_length then
    console_log("Error. area_size_calculate() -> z_length")
    return false
  end

  return (x_length * z_length)
end -- area_size_calculate

-------------------------------------------------------------------------------

function distance_2v(a_p1, a_p2)
--
  if a_p1 == nil or a_p2 == nil then
    return false
  end

  if a_p1 >= 0 and a_p2 >= 0 then
    return math.abs(a_p1 - a_p2)
  elseif a_p1 < 0 and a_p2 >= 0 then
    return (a_p2 - a_p1)
  elseif a_p1 < 0 and a_p2 <= 0 then
    return math.abs(a_p1 - a_p2)
  elseif a_p1 >= 0 and a_p2 < 0 then
    return (a_p1 - a_p2)
  end

  return false
end -- distance_2v

-------------------------------------------------------------------------------

function player_clean_data(Player)
-- Remove all player relative data

  g_player_data[Player:GetWorld():GetName()][Player:GetUUID()] = nil

  return true
end

-------------------------------------------------------------------------------

function player_save_area(Player, area_name)
-- Write down data into database
-- return false on error
-- x1, z1 - corner A, x3, z3 - corner C

  if area_name == nil then
    console_log("Error. player_save_area() -> area_name == nil")
    return false
  end

  -- Get corners A and C from g_tmp_db
  local x1, z1, x3, z3 = area_get_main_corners(Player)

  -- Recalculate selected area size
  local area_size = area_size_calculate(Player)

  -- Prepare insert operator
  local sql = [=[
    INSERT INTO area(world, uuid, x1, z1, x3, z3, area_size, area_name)
    VALUES(:world, :uuid, :x1, :z1, :x3, :z3, :area_size, :area_name);
  ]=]

  local stmt = private_db:prepare(sql)

  if not stmt then
    console_log("Error. player_save_area() -> private_db:prepare(".. sql ..")")
    return false
  end

  local ret = stmt:bind_names(
  {
    world = Player:GetWorld():GetName(),
    uuid = Player:GetUUID(),
    x1 = x1,
    z1 = z1,
    x3 = x3,
    z3 = z3,
    area_size = area_size,
    area_name = area_name
  })

  if ret ~= sqlite3.OK then
    console_log("Error. player_save_area() -> stmt:bind_names")
    return false
  end

  -- Create next step for data write
  ret = stmt:step()
  if ret ~= sqlite3.OK and ret ~= sqlite3.DONE then
    console_log("Error. player_save_area() -> stmt:step() code = ".. ret)
    return false
  end

  -- Finish him!
  if stmt:finalize() ~= sqlite3.OK then
    console_log("Error. player_save_area() -> stmt:finalize()")
    return false
  end

  return true
end

-------------------------------------------------------------------------------

function console_log(a_msg)
  LOG(MsgSuffix .. a_msg)
end

-------------------------------------------------------------------------------

function area_corners_calculate(Player)
-- Calculate all four corners for area
-- Area have 4 corners (x, y) from left to right, from up to down.
--[[

A ---> B

       |
       |
       v

D <--- C

--]]

  -- Check Player object
  if not Player then
    return false
  end

  local x1, z1, x2, z2 = area_corners_2v(Player)

  local min_x = math.min(x1, x2)
  local max_x = math.max(x1, x2)
  local min_z = math.min(z1, z2)
  local max_z = math.max(z1, z2)

  -- Point A
  local x01 = min_x
  local z01 = max_z

  -- Point B
  local x02 = max_x
  local z02 = max_y

  -- Point C
  local x03 = max_x
  local z03 = min_z

  -- Point D
  local x04 = min_z
  local z04 = min_z

  --
  -- Update records into temp DB
  --
  local sql = [=[
    UPDATE data
    SET x01 = :x01, z01 = :z01,
        x02 = :x02, z02 = :z02,
        x03 = :x03, z03 = :z03,
        x04 = :x04, z04 = :z04
    WHERE world = :world AND uuid = :uuid and mark=1;
  ]=]

  local stmt = g_tmp_db:prepare(sql)

  if not stmt then
    console_log("Error. area_corners_calculate() -> g_tmp_db:prepare()")
    return false
  end

  -- Bind values
  local ret = stmt:bind_names(
  {
    world = Player:GetWorld():GetName(),
    uuid = Player:GetUUID(),
    x01 = x01,
    z01 = z01,
    x02 = x02,
    z02 = z02,
    x03 = x03,
    z03 = z03,
    x04 = x04,
    z04 = z04
  })

  if ret ~= sqlite3.OK then
    console_log("Error. area_corners_calculate() -> stmt:bind_names")
    return false
  end

  -- Execute statement
  ret = stmt:step()

  if ret ~= sqlite3.DONE and ret ~= sqlite3.ROW then
    console_log("Error. area_corners_calculate() - > stmt:step(). Error code: " .. ret)
    return false
  end

  if stmt:finalize() ~= sqlite3.OK then  -- Finish him!
    console_log("Error. area_corners_calculate() -> stmt:finalize()")
    return false
  end

  return true
end -- area_corners_calculate

-------------------------------------------------------------------------------

function show_database()
-- Show database record

  local out = {}
  local n = 1

  -- local ret_rows_count = " LIMIT " .. math.floor(tonumber(Split[3]) or 30)

  local ret_rows_count = 0

  -- Display the database
  for row in g_tmp_db:nrows("SELECT * from data;") do
    out[n] = row.world .. " | " .. row.uuid .. " | " .. row.mark .. " | ".. row.x1 .." | " .. row.y1 .." | " .. row.z1 .." | ".. row.x2 .." | " .. row.y2 .." | " .. row.z2
    n = n + 1
  end

  return true, table.concat(out, "\n")
end

-------------------------------------------------------------------------------

function is_mark_exists(Player)
-- Check is it already activated mark action
-- Is it mark exists

  local records_count = 0 -- save rows count into database

  local stmt = g_tmp_db:prepare("SELECT count(*) from data WHERE world=? and uuid=? and mark=1;")

  if not stmt then
    console_log("Error. is_mark_exists(). Into prepere")
    player_message_error(Player)
    return false
  end

  --
  -- Bind values for SQL statements
  --

  if stmt:bind(1, Player:GetWorld():GetName()) ~= sqlite3.OK then
    Player:SendMessage("Some error. Can\'t mark area. Talk admin")
    console_log("Error. is_mark_exists. Can\'t bind value #1 for SQL statement")
    return false
  end

  if stmt:bind(2, Player:GetUUID()) ~= sqlite3.OK then
    Player:SendMessage("Some error. Can\'t mark area. Talk admin")
    console_log("Error. is_mark_exists. Can\'t bind value #2 for SQL statement")
    return false
  end

  --
  -- Try to execute SQL statement
  --

  local ret = stmt:step()

  if ret ~= sqlite3.DONE and ret ~= sqlite3.ROW then
    Player:SendMessage("Some error. Can\'t mark area. Talk admin")
    console_log("Error. is_mark_exists. Can\'t execute stmt:step() for SQL statement. Error code: " .. ret)
    return false
  end

  records_count = stmt:get_value(0)

  if stmt:finalize() ~= sqlite3.OK then  -- Finish him!
    Player:SendMessage("Some error. Can\'t mark area. Talk admin")
    console_log("Error. is_mark_exists. Can\'t stmt:finalize() for SQL statement")
    return false
  end

  if records_count == 0 then
    return false
  end

  -- All right - record exists
  return true
end

-------------------------------------------------------------------------------

function clean_player_data(Player)
-- Delete record from memmory database

  if not Player then
    console_log("Error. clean_player_data() -> Player is nil")
    return false
  end

  local stmt = g_tmp_db:prepare("DELETE FROM data WHERE world = :world AND uuid = :uuid;")

  if not stmt then
    console_log("Error. clean_player_data() -> prepere")
    player_message_error(Player)
    return false
  end

  local ret = stmt:bind_names(
  {
    world = Player:GetWorld():GetName(),
    uuid = Player:GetUUID()
  })

  if ret ~= sqlite3.OK then
    console_log("Error. clean_player_data(). Can\'t bind values")
    player_message_error(Player)
    return false
  end

  --
  -- Try to execute SQL statement
  --

  local ret = stmt:step()

  if ret ~= sqlite3.DONE and ret ~= sqlite3.ROW and ret ~= sqlite3.OK then
    player_message_error(Player)
    console_log("Error. clean_player_data() -> stmt:step()")
    return false
  end

  -- Clean statement
  if stmt:finalize() ~= sqlite3.OK then
    console_log("Error. clean_player_data() -> stmt:finalize()")
    player_message_error(Player)
    return false
  end

  return true
end

-------------------------------------------------------------------------------

function player_message_error(Player, msg)
-- Send player internal error message

  if msg == nil or msg == nil then
    Player:SendMessageInfo("Some error. Say to admin")
    return true
  else
    Player:SendMessageInfo(msg)
  end

  return true
end

-------------------------------------------------------------------------------

function save_corner_position(Player, corner_id, BlockX, BlockY, BlockZ)
-- Write down user selected point
-- corner_id - 1 or 2

  -- Check empty Player
  if not Player then
    player_message_error(Player)
    console_log("Error. save_corner_position() -> empty Player")
    return false
  end

  -- Unknown corner selected :>
  if corner_id ~= 1 and corner_id ~= 2 then
    player_message_error(Player)
    console_log("Error. save_corner_position() -> corner_id != 1 or  corner_id != 2. corner_id = ".. corner_id)
    return false
  end

  -- If y > 255 or y < 0 - error
  if BlockY > 255 or BlockY < 0 then
    console_log("Warning: save_corner_position() -> BlockY > 255 or BlockY < 0")
    return false
  end

  -- Prepare statement
  local sql = "UPDATE data "
  sql = sql .. "SET x".. corner_id .."=:x, y".. corner_id .."=:y, z".. corner_id .."=:z "
  sql = sql .. "WHERE world=:world AND uuid=:uuid AND mark=1;"

  local stmt = g_tmp_db:prepare(sql)

  if not stmt then
    player_message_error(Player)
    console_log("Error. save_corner_position() -> prepare(".. sql ..")")
    return false
  end

  -- Execute with data
  local ret = stmt:bind_names(
  {
    world=Player:GetWorld():GetName(),
    uuid=Player:GetUUID(),
    x=BlockX,
    y=BlockY,
    z=BlockZ
  })

  if ret ~= sqlite3.OK then
    player_message_error(Player)
    console_log("Error. save_corner_position() -> virtual step")
    return false
  end

  stmt:step()
  stmt:finalize()

  return true
end

-------------------------------------------------------------------------------

function area_corners_2v(Player)
-- Return player selected corners

  local sql = [=[
    SELECT x1, z1, x2, z2
    FROM data
    WHERE world = :world AND uuid = :uuid AND mark = 1;
  ]=]

  local stmt = g_tmp_db:prepare(sql)

  if not stmt then
    console_log("Error. area_corners_2v() -> g_tmp_db:prepare(sql)")
    return false
  end

  local ret = stmt:bind_names(
  {
    world = Player:GetWorld():GetName(),
    uuid = Player:GetUUID()
  })

  if ret ~= sqlite3.OK then
    console_log("Error. area_corners_2v() -> stmt:bind_names")
    return false
  end

  local ret = stmt:step()

  if ret ~= sqlite3.DONE and ret ~= sqlite3.ROW then
    console_log("Error. area_corners_2v() -> stmt:step(). Code".. ret)
    return false
  end

  local x1 = stmt:get_value(0)
  local z1 = stmt:get_value(1)
  local x2 = stmt:get_value(2)
  local z2 = stmt:get_value(3)

  if stmt:finalize() ~= sqlite3.OK then  -- Finish him!
    console_log("Error. area_corners_2v() -> stmt:finalize()")
    return false
  end

  return x1, z1, x2, z2
end -- area_corners_2v

-------------------------------------------------------------------------------

function is_area_selected(Player)
-- Return true if 2 point of area selected

  -- Prepera statement
  local sql =[=[
    SELECT count(*)
    FROM data
    WHERE world = :world AND uuid = :uuid AND mark = 1
          AND x1 IS NOT NULL AND y1 IS NOT NULL AND z1 IS NOT NULL
          AND x2 IS NOT NULL AND y2 IS NOT NULL AND z2 IS NOT NULL;
  ]=]

  local stmt = g_tmp_db:prepare(sql)

  if not stmt then
    console_log("Error. is_area_selected() -> g_tmp_db:prepare()")
    player_message_error(Player)
    return false
  end

  -- Bind values
  local ret = stmt:bind_names(
  {
    world = Player:GetWorld():GetName(),
    uuid = Player:GetUUID()
  })

  if ret ~= sqlite3.OK then
    console_log("Error. is_area_selected() -> stmt:bind_names")
    player_message_error(Player)
    return false
  end

  -- Execute statement
  ret = stmt:step()

  if ret ~= sqlite3.DONE and ret ~= sqlite3.ROW then
    console_log("Error. is_area_selected() - > stmt:step(). Error code: " .. ret)
    player_message_error(Player)
    return false
  end

  if stmt:get_value(0) ~= 1 then
    return false
  end

  return true
end

-------------------------------------------------------------------------------

function area_get_main_corners(Player)
-- Return main coreners coordinates
-- Main corners is A and C corner

  local sql = [=[
    SELECT x01, z01, x03, z03
    FROM data
    WHERE world = :world AND uuid = :uuid AND mark=1;
  ]=]

  local stmt = g_tmp_db:prepare(sql)

  if not stmt then
    console_log("Error. area_get_main_corners() -> g_tmp_db:prepare(".. sql ..")")
    return false
  end

  local ret = stmt:bind_names(
  {
    world = Player:GetWorld():GetName(),
    uuid = Player:GetUUID()
  })

  if ret ~= sqlite3.OK then
    console_log("Error. area_get_main_corners() -> stmt:bind_names")
    return false
  end

  ret = stmt:step()

  if ret ~= sqlite3.DONE and ret ~= sqlite3.ROW then
    console_log("Error. area_get_main_corners() -> stmt:step()")
    return false
  end

  local x1 = stmt:get_value(0)
  local z1 = stmt:get_value(1)
  local x3 = stmt:get_value(2)
  local z3 = stmt:get_value(3)

  if stmt:finalize() ~= sqlite3.OK then  -- Finish him!
    console_log("Error. area_get_main_corners() -> stmt:finalize()")
    return false
  end

  return x1, z1, x3, z3
end -- area_get_main_corners

-------------------------------------------------------------------------------

function is_area_has_owner(Player)
-- Check is it selected area has owner
-- return:
--    (-1) - error
--    1 - owner exists
--    0 - owner does not exists

  if not Player then
    return (-1)
  end

  local x1, z1, x2, z2, x3, z3, x4, z4 = area_corners_4v(Player)

  local function execute_sql(a_sql)
    -- execute SQL statement
    if a_sql == '' or a_sql == nil then
      return (-1)
    end

    -- Prepare
    local stmt = private_db:prepare(a_sql)

    if not stmt then
      console_log("Error. is_area_has_owner() -> execute_sql() -> private_db:prepare(".. a_sql ..")")
      return (-1)
    end

    -- Bind variables
     local ret = stmt:bind_names({
        x1 = x1, z1 = z1,
        x2 = x2, z2 = z2,
        x3 = x3, z3 = z3,
        x4 = x4, z4 = z4,
        world = Player:GetWorld():GetName()
     })

    if ret ~= sqlite3.OK then
      console_log("Error. is_area_has_owner() -> execute_sql() -> stmt:bind_names()")
      return (-1)
    end

    ret = stmt:step()

    if ret ~= sqlite3.DONE and ret ~= sqlite3.ROW then
      console_log("Error. is_area_has_owner() -> execute_sql() -> stmt:step(). Ret code: " .. ret)
      return (-1)
    end

    if stmt:get_value(0) ~= 0 then
      stmt:finalize()
      return 1
    end

    if stmt:finalize() ~= sqlite3.OK then  -- Finish him!
      console_log("Error. is_area_has_owner() -> execute_sql() -> stmt:finalize()")
      return (-1)
    end

    -- All right
    return 0
  end -- execute_sql()

  ---------------------------
  -- Inner area. New area corner into exists area
  ---------------------------

  -- Check into protected areas
  local sql = [=[
    SELECT count(*) FROM area
    WHERE
      world = :world AND
      (
      ((x1 <= :x1 AND z1 >= :z1) AND (x3 >= :x1 AND z1 >= :z1) AND (x3 >= :x1 AND z3 <= :z1) AND (x1 <= :x1 AND z3 <= :z1)) OR
      ((x1 <= :x2 AND z1 >= :z2) AND (x3 >= :x2 AND z1 >= :z2) AND (x3 >= :x2 AND z3 <= :z2) AND (x1 <= :x2 AND z3 <= :z2)) OR
      ((x1 <= :x3 AND z1 >= :z3) AND (x3 >= :x3 AND z1 >= :z3) AND (x3 >= :x3 AND z3 <= :z3) AND (x1 <= :x3 AND z3 <= :z3)) OR
      ((x1 <= :x4 AND z1 >= :z4) AND (x3 >= :x4 AND z1 >= :z4) AND (x3 >= :x4 AND z3 <= :z4) AND (x1 <= :x4 AND z3 <= :z4))
      )
  ]=]

  local ret_exe_sql = execute_sql(sql)

  if ret_exe_sql < 0 then
    -- have some error
    return (-1)
  elseif ret_exe_sql == 1 then
    -- Owner exists
    return 1
  end

  ---------------------------------------------------------------------------------
  -- New area cross exists area and corner exists area into new area
  ---------------------------------------------------------------------------------

  sql = [=[
    SELECT count(*) FROM area WHERE
      world = :world AND
      (
      ((x1 >= :x1 AND z1 <= :z1) AND (x1 <= :x3 AND z1 <= :z1) AND (x1 <= :x3 AND z1 >= :z1) AND (x1 >= :x1 AND z1 >= :z3)) OR
      ((x3 >= :x1 AND z1 <= :z1) AND (x3 <= :x3 AND z1 <= :z1) AND (x3 <= :x3 AND z1 >= :z1) AND (x3 >= :x1 AND z1 >= :z3)) OR
      ((x3 >= :x1 AND z3 <= :z1) AND (x3 <= :x3 AND z3 <= :z1) AND (x3 <= :x3 AND z3 >= :z1) AND (x3 >= :x1 AND z3 >= :z3)) OR
      ((x1 >= :x1 AND z3 <= :z1) AND (x1 <= :x3 AND z3 <= :z1) AND (x1 <= :x3 AND z3 >= :z1) AND (x1 >= :x1 AND z3 >= :z3))
      )
  ]=]

  -- local ret_exe_sql = execute_sql(sql)

  if ret_exe_sql < 0 then
    -- have some error
    return (-1)
  elseif ret_exe_sql == 1 then
    -- Owner exists
    return 1
  end

  ---------------------------
  -- Horizontal intersection AND Vertical intersection
  ---------------------------

  sql = [=[
    SELECT count(*) FROM area WHERE
    world = :world AND
    (
    ((x1 <= :x1 AND z1 <= :z1) AND (x3 >= :x3 AND z3 >= :z3)) OR
    ((x1 >= :x1 AND z1 >= :z1) AND (x3 <= :x3 AND z3 <= :z3))
    )
  ]=]

  local ret_exe_sql = execute_sql(sql)

  if ret_exe_sql < 0 then
    -- Have some error
    return (-1)
  elseif ret_exe_sql == 1 then
    -- Owner exists
    return 1
  end

  ---------------------------
  -- New area outer of exists
  ---------------------------
  sql = [=[

  SELECT count(*) FROM area WHERE
  world = :world AND
  (
  ((x1 >= :x1 AND z1 <= :z1) AND (x1 <= :x3 AND z1 >= :z3)) OR
  ((x3 >= :x1 AND z1 <= :z1) AND (x3 <= :x3 AND z1 >= :z3)) OR
  ((x3 >= :x1 AND z3 <= :z1) AND (x3 <= :x3 AND z3 >= :z3)) OR
  ((x1 >= :x1 AND z3 <= :z1) AND (x1 <= :x3 AND z3 >= :z3))
  )
  ]=]

  local ret_exe_sql = execute_sql(sql)

  if ret_exe_sql < 0 then
    -- Have some error
    return (-1)
  elseif ret_exe_sql == 1 then
    -- Owner exists
    return 1
  end

  -- No owner found
  return 0
end -- is_area_has_owner

-------------------------------------------------------------------------------

function area_corners_4v(Player)
-- Return coordinates (4 point, 8 coordinates) selected area

  local sql = [=[
    SELECT x01, z01, x02, z02, x03, z03, x04, z04
    FROM data
    WHERE world = :world AND uuid = :uuid AND mark = 1;
  ]=]

  local stmt = g_tmp_db:prepare(sql)

  if not stmt then
    console_log("Error. area_corners_4v() -> g_tmp_db:prepare(".. sql ..")")
    return false
  end

  local ret = stmt:bind_names(
  {
    world = Player:GetWorld():GetName(),
    uuid = Player:GetUUID()
  })

  if ret ~= sqlite3.OK then
    console_log("Error. area_corners_4v() -> stmt:bind_names")
    return false
  end

  local ret = stmt:step()

  if ret ~= sqlite3.DONE and ret ~= sqlite3.ROW then
    console_log("Error. area_corners_4v() -> stmt:step(). Code".. ret)
    return false
  end

  local x1 = stmt:get_value(0)
  local z1 = stmt:get_value(1)
  local x2 = stmt:get_value(2)
  local z2 = stmt:get_value(3)
  local x3 = stmt:get_value(4)
  local z3 = stmt:get_value(5)
  local x4 = stmt:get_value(6)
  local z4 = stmt:get_value(7)

  if stmt:finalize() ~= sqlite3.OK then  -- Finish him!
    console_log("Error. area_corners_4v() -> stmt:finalize()")
    return false
  end

  return x1, z1, x2, z2, x3, z3, x4, z4
end

-------------------------------------------------------------------------------

function check_block_access(Player, BlockX, BlockY, BlockZ)
-- Check player access to block
-- 1 - player has access, 0 - no access

  local sql = [=[
  SELECT count(*) FROM area WHERE
  (world = :world AND uuid <> :uuid) AND
  (
    (x1 <= :x1 AND z1 >= :z1) AND (x3 >= :x1 AND z3 <= :z1)
  )
  ]=]

-- Prepare
    local stmt = private_db:prepare(sql)

    if not stmt then
      console_log("Error. check_block_access() -> private_db:prepare(".. sql ..")")
      return (-1)
    end

    -- Bind variables
     local ret = stmt:bind_names({
        x1 = math.floor(BlockX),
        z1 = math.floor(BlockZ),
        world = Player:GetWorld():GetName(),
        uuid = Player:GetUUID()
     })

    if ret ~= sqlite3.OK then
      console_log("Error. check_block_access()() -> stmt:bind_names()")
      return (-1)
    end

    ret = stmt:step()

    if ret ~= sqlite3.DONE and ret ~= sqlite3.ROW then
      console_log("Error. check_block_access()() -> stmt:step(). Ret code: " .. ret)
      return (-1)
    end

    if stmt:get_value(0) ~= 0 then
      stmt:finalize()
      return 0
    end

    if stmt:finalize() ~= sqlite3.OK then  -- Finish him!
      console_log("Error. check_block_access() -> stmt:finalize()")
      return (-1)
    end

  return 1
end

-------------------------------------------------------------------------------

function CommandList(Split, Player)
-- List player's areas.

  -- Check Player object not emty
  if not Player then
    console_log("AreaList empty Player object")
    player_message_error(Player)
    return true
  end

  -- Get areas names
  sql = [=[
    SELECT area_name, area_size FROM area WHERE
    world = :world AND uuid = :uuid;
  ]=]

  local stmt = private_db:prepare(sql)

  if not stmt then
    console_log("Error. AreaList() -> private_db:prepare(".. sql ..")")
    return true
  end

  -- Bind variables
  local ret = stmt:bind_names({
     world = Player:GetWorld():GetName(),
     uuid = Player:GetUUID()
  })

  if ret ~= sqlite3.OK then
    console_log("Error. AreaList() -> stmt:bind_names()")
    stmt:finalize()
    return true
  end

  local area_name = nil
  local area_size = nil

  Player:SendMessageInfo("Your private areas:")
  Player:SendMessageInfo("    Name     |     Size     |")
  for area_name, area_size in stmt:urows() do
    Player:SendMessageInfo(area_name .."  |  ".. area_size)
  end

  if stmt:finalize() ~= sqlite3.OK then  -- Finish him!
    console_log("Error. AreaList() -> stmt:finalize()")
    return true
  end

  return true
end -- CommandList

-------------------------------------------------------------------------------

function CommandDelete(Split, Player)
-- Delete players private area

  -- Check Player object not emty
  if not Player then
    console_log("CommandDelete empty Player object")
    player_message_error(Player)
    return true
  end

  -- Check is area_name not empty
  if Split[3] == nil or Split[3] == '' then
    player_message_error(Player, "Set area name, please")
    return true
  end

  -- Get areas names
  sql = [=[
    DELETE FROM area WHERE
    world = :world AND uuid = :uuid AND area_name = :area_name;
  ]=]

  local stmt = private_db:prepare(sql)

  if not stmt then
    console_log("Error. CommandDelete() -> private_db:prepare(".. sql ..")")
    player_message_error(Player)
    return true
  end

  -- Bind variables
  local ret = stmt:bind_names({
    world = Player:GetWorld():GetName(),
    uuid = Player:GetUUID(),
    area_name = Split[3]
  })

  if ret ~= sqlite3.OK then
    console_log("Error. CommandDelete() -> stmt:bind_names()")
    player_message_error(Player)
    stmt:finalize()
    return true
  end

  ret = stmt:step()

  if ret ~= sqlite3.DONE and ret ~= sqlite3.ROW then
    console_log("Error. CommandDelete() -> stmt:step(). Ret code: " .. ret)
    player_message_error(Player)
    return true
  end

  if stmt:finalize() ~= sqlite3.OK then  -- Finish him!
    console_log("Error. AreaList() -> stmt:finalize()")
    return true
  end

  return true
end -- CommandDelete

-------------------------------------------------------------------------------

function player_get_config(Player)
--

  local func_name = "player_config()"

  local areas_count = g_DEFAULT_MAX_AREA_COUNT
  local areas_total_size = g_MAX_TOTAL_AREA_SIZE


  if not Player then
    console_log("Error. Empty player in ".. func_name)
    player_message_error(Player)
    return (-1)
  end

  sql = [=[
    SELECT areas_count, areas_total_size
    FROM config
    WHERE world = :world AND uuid = :uuid;
  ]=]

  local stmt = private_db:prepare(sql)

  if not stmt then
    console_log("Error. ".. func_name .." -> private_db:prepare(".. sql ..")")
    player_message_error(Player)
    return (-1)
  end

  -- Bind variables
  local ret = stmt:bind_names({
     world = Player:GetWorld():GetName(),
     uuid = Player:GetUUID()
  })

  if ret ~= sqlite3.OK then
    console_log("Error. ".. func_name .." -> stmt:bind_names()")
    stmt:finalize()
    return (-1)
  end

  ret = stmt:step()

  if ret ~= sqlite3.DONE and ret ~= sqlite3.ROW then
    console_log("Error. ".. func_name .." -> stmt:step(). Error code: " .. ret)
    player_message_error(Player)
    stmt:finalize()
    return (-1)
  end

  -- If no record found - use default value. If not found - create default value
  if rel == sqlite3.DONE then
    stmt:reset()

    ret = stmt:bind_names({
      world = Player:GetWorld():GetName(),
      uuid = "Default"
    })

    ret = stmt:step()

    -- Creaate default record into database
    if ret == sqlite3.DONE and ret ~= sqlite3.ROW then
      create_default_config()
    else
      areas_count = stmt:get_value(0)
      areas_total_size = stmt:get_value(1)
    end
  elseif ret == sqlite3.ROW then
    areas_count = stmt:get_value(0)
    areas_total_size = stmt:get_value(1)
  end

  if stmt:finalize() ~= sqlite3.OK then  -- Finish him!
    console_log("Error. ".. func_name .." -> stmt:finalize()")
    return (-1)
  end

  return areas_count, areas_total_size
end -- player_get_config

-------------------------------------------------------------------------------

function create_default_config()
-- Create default config records

  local func_name = "create_default_config() -> empty function"

  console_log("Setup default config data. If not exists")

  cRoot:Get():ForEachWorld(
    function(a_World)

      -------------------------------------
      -- check is it Default record exists
      -------------------------------------

      sql = [=[
        SELECT count(*) FROM config
        WHERE world = :world;
      ]=]

      local stmt = private_db:prepare(sql)

      if not stmt then
        console_log("Error. ".. func_name .." -> private_db:prepare(".. sql ..")")
        return (-1)
      end

      -- Bind values
      local ret = stmt:bind_names(
      {
        world = a_World:GetName()
      })

      if ret ~= sqlite3.OK then
        console_log("Error. ".. func_name .." -> stmt:bind_names")
        return (-1)
      end

      -- Execute statement
      ret = stmt:step()

      if ret ~= sqlite3.DONE and ret ~= sqlite3.ROW then
        console_log("Error. ".. func_name .." - > stmt:step(). Error code: " .. ret)
        return (-1)
      end

      if stmt:get_value(0) > 0 then
        return true
      end

      -----------------------------------------
      -- if record does not exists - create it
      -----------------------------------------

      console_log("Create default config for world: ".. a_World:GetName())

      sql = [=[
        INSERT INTO config(world, uuid, areas_count, areas_total_size)
        VALUES(:world, "Default", :areas_count, :areas_total_size)
      ]=]

      local stmt = private_db:prepare(sql)

      if not stmt then
        console_log("Error. ".. func_name .." -> private_db:prepare(".. sql ..")")
        return (-1)
      end

      local ret = stmt:bind_names(
      {
        world = a_World:GetName(),
        areas_count = g_DEFAULT_MAX_AREA_COUNT,
        areas_total_size = g_MAX_TOTAL_AREA_SIZE
      })

      if ret ~= sqlite3.OK then
        console_log("Error. ".. func_name .." -> stmt:bind_names")
        stmt:finalize()
        return false
      end

      -- Create next step for data write
      ret = stmt:step()

      if ret ~= sqlite3.OK and ret ~= sqlite3.DONE then
        console_log("Error. ".. func_name .." -> stmt:step() code = ".. ret)
        stmt:finalize()
        return false
      end

      -- Finish him!
      if stmt:finalize() ~= sqlite3.OK then
        console_log("Error. ".. func_name .." -> stmt:finalize()")
        return false
      end
    end -- <no name function>
  );


  return true
end -- create_default_config

-------------------------------------------------------------------------------

function player_areas_count(a_player)
-- Return count player's private areas

  func_name = "player_areas_count()"

  if not a_player then
    console_log("Error. ".. func_name .." object a_player is empty")
    return (-1)
  end

  local sql = [=[
    SELECT count(*)
    FROM area
    WHERE world = :world AND uuid = :uuid;
  ]=]

  local stmt = private_db:prepare(sql)

  if not stmt then
    console_log("Error. ".. func_name .." -> private_db:prepare(".. sql ..")")
    return (-1)
  end

  -- Bind values
  local ret = stmt:bind_names(
  {
    world = a_player:GetWorld():GetName(),
    uuid = a_player:GetUUID()
  })

  if ret ~= sqlite3.OK then
    console_log("Error. ".. func_name .." -> stmt:bind_names")
    stmt:finalize()
    return (-1)
  end

  -- Execute statement
  ret = stmt:step()

  if ret ~= sqlite3.DONE and ret ~= sqlite3.ROW then
    console_log("Error. ".. func_name .." - > stmt:step(). Error code: " .. ret)
    stmt:finalize()
    return (-1)
  end

  local areas_count = stmt:get_value(0)

  stmt:finalize()

  return areas_count
end

-------------------------------------------------------------------------------

-- function private_db_tmp_create()
-- -- Create temporary in-memory datatabase and copy data from private database
--
--   g_private_db_tmp = sqlite3.open_memory()
--   if not g_private_db_tmp then
--     console_log("Error. private_db_tmp_create() -> sqlite3.open_memory()")
--     return false
--   end
--
--   return true
-- end

-------------------------------------------------------------------------------

-- I wrote it for a quick hand. Optimtzation needed and, maybe, data store process

-------------------------------------------------------------------------------


