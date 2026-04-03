# AAExport
Macroquest lua script for importing and exporting purchased AAs

Download to your lua folder, the path should be /macroquest/lua/AAExport/init.lua

Lua package manager will prompt to install luafilesystem on the first run, that's used for interacting with export files (lines 97 and 1025, if you want to verify file operations before installing the package).

Supported modes:

- **Export Purchased**: will output an ini file in /macroquest/lua/AAExport/exports/AA_charname_date_time.ini containing currently purchased AA's in the schema:
  - ${AATab} | ${AAName} | ${AACurrentRank} | ${AAMaxRanks} | ${AACost} | ${AltActCode}
  - Example: AA1002=General|Combat Stability|8|39|5|33|
  - For re-importing, only the AA Tab, AA Name, and AA Current rank are relevant (if you want to craft your own import files). Cost is captured at the time of export and may not reflect all ranks.
- **Export All**: will export all available AAs in the same format as Purchased
- **Export Can Purchase**: will export all AAs available for purchase in the same format as Purchased
- **Export Descriptions**: will export all AAs with the addition of a Description field, can be useful for building theorycrafting sheets or parsing pre-reqs
  - Example: AA1009=General|Combat Stability|8|39|5|33|This is a passive ability; it does not need to be activated.<BR>Requirements: Level: 1,  No previous ability requirements.<BR>The first three ranks of this ability increase melee damage mitigation by 2, 5, and 10 percent.  Additional ranks further increase this effect.

**Edit Mode** allows in-game modifications of exported files in case you want to change ranks or remove AAs before re-importing

<img width="899" height="803" alt="image" src="https://github.com/user-attachments/assets/358a1fd3-e00a-4841-8f8b-b10a221b36fc" />
