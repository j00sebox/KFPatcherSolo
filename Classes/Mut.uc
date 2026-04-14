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

var private transient array<PlayerController> GreetedPCs;

struct sPendingGreeting {
    var PlayerController pc;
    var string msg;
    var int repeatsLeft;
};
var private transient array<sPendingGreeting> PendingGreetings;

//=============================================================================
event PreBeginPlay() {
    super.PreBeginPlay();

    class'hookPawn'.default.cashtimer = 0.0f;

    // restore any lingering bytecodes from a previous game before re-applying
    RestoreAllFunctions();

    // apply replacements fresh
    // Standalone and ListenServer spawn the mutator via ?Mutator= during InitGame,
    // so replacing KFGameType/Engine/xGame bytecodes mid-call stack crashes.
    // Only dedicated servers loading via ServerActor are safe for the full replacement.
    if (Level.NetMode == NM_DedicatedServer) {
        ReplaceFunctionArray(List);
    } else {
        ReplaceFunctionArraySafe(List);
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

// one-shot "mod loaded" message per player so they know the mutator is active
function ModifyPlayer(Pawn Other) {
    local PlayerController pc;
    local int i;

    super.ModifyPlayer(Other);

    if (Other == none)
        return;

    pc = PlayerController(Other.Controller);
    if (pc == none)
        return;

    for (i = 0; i < GreetedPCs.length; i++) {
        if (GreetedPCs[i] == pc)
            return;
    }

    SendStartupMessage(pc);
    GreetedPCs[GreetedPCs.length] = pc;
}

// Send the greeting now, then queue it to repeat a couple more times so it
// stays visible in chat longer than the ~6s hardcoded HUD fade.
private final function SendStartupMessage(PlayerController pc) {
    local int count, idx;
    local sPendingGreeting entry;

    count = class'Settings'.default.StartupMessages.length;
    if (count == 0)
        return;

    idx = Rand(count);
    entry.msg = class'Settings'.default.StartupMessages[idx];
    entry.pc = pc;
    entry.repeatsLeft = 2;

    class'Utility'.static.SendMessage(pc, entry.msg, false);
    PendingGreetings[PendingGreetings.length] = entry;

    SetTimer(3.0, true);
}

function Timer() {
    local int i;

    for (i = PendingGreetings.length - 1; i >= 0; i--) {
        if (PendingGreetings[i].pc == none) {
            PendingGreetings.Remove(i, 1);
            continue;
        }
        class'Utility'.static.SendMessage(PendingGreetings[i].pc, PendingGreetings[i].msg, false);
        PendingGreetings[i].repeatsLeft--;
        if (PendingGreetings[i].repeatsLeft <= 0)
            PendingGreetings.Remove(i, 1);
    }

    if (PendingGreetings.length == 0)
        SetTimer(0, false);
}

// standalone disconnect: Logout -> NotifyLogout fires before level teardown
function NotifyLogout(Controller Exiting) {
    local int i;

    log("> NotifyLogout fired for" @ Exiting);

    for (i = GreetedPCs.length - 1; i >= 0; i--) {
        if (GreetedPCs[i] == none || GreetedPCs[i] == Exiting)
            GreetedPCs.Remove(i, 1);
    }

    for (i = PendingGreetings.length - 1; i >= 0; i--) {
        if (PendingGreetings[i].pc == none || PendingGreetings[i].pc == Exiting)
            PendingGreetings.Remove(i, 1);
    }

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
