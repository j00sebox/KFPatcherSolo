/*
 * Author       : Shtoyan
 * Home Repo    : https://github.com/InsultingPros/KFPatcher
 * License      : https://www.gnu.org/licenses/gpl-3.0.en.html
 * Modified by  : j00sebox, 2026 (KFPatcherSolo fork)
*/
class Mut extends Mutator
    config(KFPatcherSoloFuncs);


//=============================================================================
struct FunctionRecord {
    var string Info;    // why we replace this function
    var string Replace; // original function with format "package.class.target_function"
    var string With;    // replacement function with format "class.new_function"
};
var private config array<FunctionRecord> List;

var private UFunctionCast FunctionCaster;

// only allowed players can use mutate commands
var private array<string> AllowedSteamID;

// bytecode backups — stored in class defaults so they persist across level transitions
// (cleanup hooks like Destroyed/ServerTraveling never fire when backing out to menu)
struct sFunctionBackup {
    var private uFunction originalFunction;
    var private array<byte> originalScript;
};
var private array<sFunctionBackup> ProcessedFunctions;

var private transient bool bStartupMessageSent;

//=============================================================================
event PreBeginPlay() {
    super.PreBeginPlay();

    class'hookPawn'.default.cashtimer = 0.0f;

    // restore any lingering bytecodes from a previous game before re-applying
    RestoreAllFunctions();

    // apply replacements fresh
    if (Level.NetMode == NM_Standalone) {
        ReplaceFunctionArraySafe(List);
    } else {
        ReplaceFunctionArray(List);
    }
}

// function replacement, skipping functions unsafe in standalone mode
// InitGame is on the call stack when mutators are spawned via ?Mutator=
// KFGameType state functions can also cause issues when bytecodes persist
private final function ReplaceFunctionArraySafe(array<FunctionRecord> functionList) {
    local int idx;

    for (idx = 0; idx < functionList.length; idx++) {
        if (InStr(functionList[idx].Replace, "KFGameType.") != -1) {
            log("> Skipping " $ functionList[idx].Replace $ " (unsafe in standalone mode)");
            continue;
        }
        if (InStr(functionList[idx].Replace, "GameRules.") != -1) {
            log("> Skipping " $ functionList[idx].Replace $ " (unsafe in standalone mode)");
            continue;
        }
        // Engine/xGame base classes persist into the entry level after disconnect
        // and no cleanup hook fires in standalone — skip to prevent freeze
        if (InStr(functionList[idx].Replace, "Engine.") != -1) {
            log("> Skipping " $ functionList[idx].Replace $ " (unsafe in standalone mode)");
            continue;
        }
        if (InStr(functionList[idx].Replace, "xGame.") != -1) {
            log("> Skipping " $ functionList[idx].Replace $ " (unsafe in standalone mode)");
            continue;
        }
        ReplaceFunction(functionList[idx].Replace, functionList[idx].With);
    }
}

// function replacement
private final function ReplaceFunctionArray(array<FunctionRecord> functionList) {
    local int idx;

    for (idx = 0; idx < functionList.length; idx++) {
        ReplaceFunction(functionList[idx].Replace, functionList[idx].With);
    }
}

private final function ReplaceFunction(string Replace, string With) {
    local uFunction A, B;
    local sFunctionBackup functionBackup;

    DynamicLoadObject(GetClassName(Replace), class'class', true);
    DynamicLoadObject(self.class.outer.name $ "." $ Left(With, InStr(With,".")), class'class', true);

    A = default.FunctionCaster.Cast(function(FindObject(Replace, class'function')));
    B = default.FunctionCaster.Cast(function(FindObject(With, class'function')));

    if (A == none) {
        warn("Failed to process " $ Replace);
        return;
    }
    if (B == none) {
        warn("Failed to process " $ With);
        return;
    }

    // store backup in class defaults so it persists across level transitions
    functionBackup.originalFunction = A;
    functionBackup.originalScript = A.Script;
    default.ProcessedFunctions[default.ProcessedFunctions.length] = functionBackup;

    A.Script = B.Script;
    log("> Processing " $ Replace $ "    ---->    " $ With);
}

// restore all replaced functions to their original vanilla bytecodes
private final function RestoreAllFunctions() {
    local int i;

    if (default.ProcessedFunctions.length == 0)
        return;

    for (i = 0; i < default.ProcessedFunctions.length; i++) {
        default.ProcessedFunctions[i].originalFunction.Script = default.ProcessedFunctions[i].originalScript;
    }
    log("> Restored " $ default.ProcessedFunctions.length $ " functions to vanilla state");
    default.ProcessedFunctions.length = 0;
}

// get the "package + dot + class" string for DynamicLoadObject()
private final function string GetClassName(string input) {
    local array<string> parts;

    split(input, ".", parts);

    // state functions
    if (parts.length == 4) {
        ReplaceText(input, "." $ parts[2], "");
        ReplaceText(input, "." $ parts[3], "");
    }
    // non-state functions
    else {
        ReplaceText(input, "." $ parts[2], "");
    }

    return input;
}

// one-shot "mod loaded" message so the player can confirm the mutator is active
function ModifyPlayer(Pawn Other) {
    local PlayerController pc;

    super.ModifyPlayer(Other);

    if (bStartupMessageSent || Other == none)
        return;

    pc = PlayerController(Other.Controller);
    if (pc == none)
        return;

    class'Utility'.static.SendMessage(pc, "^g[KFPatcherSolo] ^wloaded successfully!", false);
    bStartupMessageSent = true;
}

// standalone disconnect: Logout -> NotifyLogout fires before level teardown
function NotifyLogout(Controller Exiting) {
    log("> NotifyLogout fired for" @ Exiting);
    if (Level.NetMode == NM_Standalone) {
        RestoreAllFunctions();
    }
    super.NotifyLogout(Exiting);
}

// dedicated server map changes
function ServerTraveling(string URL, bool bItems) {
    RestoreAllFunctions();
    super.ServerTraveling(URL, bItems);
}

function Destroyed() {
    RestoreAllFunctions();
    super.Destroyed();
}

//=============================================================================
defaultproperties {
    GroupName="KF-DarkMagic"
    FriendlyName="KF1 Patcher Solo"
    Description="Custom patches for KF1 with solo mode support."

    begin object class=UFunctionCast name=SubFunctionCaster
    end object
    FunctionCaster=SubFunctionCaster
}
