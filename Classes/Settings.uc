/*
 * Author       : Shtoyan
 * Home Repo    : https://github.com/InsultingPros/KFPatcher
 * License      : https://www.gnu.org/licenses/gpl-3.0.en.html
 * Modified by  : j00sebox, 2026 (KFPatcherSolo fork)
*/
class Settings extends object
    config(KFPatcherSoloSettings);


var() config bool bBuyEverywhere;

// player info
var() config string sAlive, sDead, sSpectator, sReady, sNotReady, sAwaiting;
var() config string sTagHP, sTagKills;
var() config bool bShowPerk;
var() config float fRefreshTime;

// zedtime
var() config bool bAllowZedTime;

// all traders
var() config bool bAllTradersOpen;
var() config string bAllTradersMessage;

// startup greeting — one is picked at random per player on first pawn spawn
var() config array<string> StartupMessages;