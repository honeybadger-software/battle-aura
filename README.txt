BATTLE AURA  v3.1.1   -   for World of Warcraft: Forever
by Honey Badger Software Designs      https://honeybadger.software

QUESTIONS, BUGS, IDEAS, OR JUST SAYING HI:  whisper  Honeybadger Software  in game (WoW Forever). All whispers welcome.

An immersive personal damage meter. Your own damage shown on a cinematic battle scene:
  * YOUR DAMAGE (the big gold number) - total damage this fight
  * BIGGEST HIT and DPS
  * every hit floats up as a number (crits bigger and hotter), shakes the frame and rings out
  * a comet runs your spark-line, embers and aura build as the fight heats up
  * a combo counter from your casts, a red flash when you are hit
  * "NEW BEST HIT / DPS / DAMAGE!" banners against your own records
Built on Blizzard's own damage meter (C_DamageMeter) - it works with Forever's restricted combat data.

INSTALL
  1. Close the game.  2. Unzip so the folder is   ...\World of Warcraft\<your Forever folder>\Interface\AddOns\BattleAura
     (inside it you should see BattleAura.toc and an Art folder).   3. Start the game.
  If the picture ever shows as a blank/green square, fully restart the game once (new texture files load at startup).

USE
  Drag the picture to move it.            /ba            show the options
  /ba scale 0.3-1.2   size of the frame   /ba font 60-200   size of the big number
  /ba aura            aura glow on/off    /ba hits          floating hit numbers on/off
  /ba grouphits       hit numbers while grouped (also shows other players' hits on your target)
  /ba best            your records        /ba test          preview every effect, no fight needed
  /ba reset           back to defaults

NOTES
  * Floating hit numbers are off by default while you are in a group, because the game reports every player's hits on a target.
  * Records and the fight log are stored only on your computer (SavedVariables). Nothing is sent anywhere.
  * Free for everyone. Please do not redistribute modified copies or sell it.
