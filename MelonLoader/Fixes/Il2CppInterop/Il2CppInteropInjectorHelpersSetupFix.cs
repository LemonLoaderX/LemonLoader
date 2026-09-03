#if NET6_0_OR_GREATER

using System;
using System.Collections.Generic;
using System.Reflection;
using HarmonyLib;
using Il2CppInterop.Runtime.Injection;

namespace MelonLoader.Fixes.Il2CppInterop
{
    // Removes hooks that are unavailable on specific desktop platforms.
    internal static class Il2CppInteropInjectorHelpersSetupFix
    {
        private static Type _injectorType;
        private static MethodInfo _setupMethod;
        private static MethodInfo _setupTranspiler;
        
        internal static void Install()
        {
            try
            {
                Type thisType = typeof(Il2CppInteropInjectorHelpersSetupFix);
                
                _injectorType = typeof(ClassInjector).Assembly.GetType("Il2CppInterop.Runtime.Injection.InjectorHelpers", false);
                if (_injectorType == null)
                    throw new Exception($"Failed to get InjectorHelpers");
                
                _setupMethod = _injectorType.GetMethod("Setup", BindingFlags.NonPublic | BindingFlags.Static);
                if (_setupMethod == null)
                    throw new Exception("Failed to get InjectorHelpers.Setup");

                MelonDebug.Msg($"Patching Il2CppInterop InjectorHelpers.Setup...");
                _setupTranspiler = thisType.GetMethod(nameof(Setup_Transpiler), BindingFlags.NonPublic | BindingFlags.Static);
                Core.HarmonyInstance.Patch(_setupMethod,
                    null,
                    null,
                    new HarmonyMethod(_setupTranspiler));
            }
            catch (Exception e)
            {
                MelonLogger.Error(e);
            }
        }
        
        private static IEnumerable<CodeInstruction> Setup_Transpiler(IEnumerable<CodeInstruction> instructions)
        {
#if OSX
            instructions = RemoveField(
                "GetTypeInfoFromTypeDefinitionIndexHook", _injectorType,
                instructions);
#endif
#if LINUX
            instructions = RemoveField(
                "GetFieldDefaultValueHook", _injectorType,
                instructions);
#endif

            return instructions;
        }

        private static IEnumerable<CodeInstruction> RemoveField(
            string targetFieldName,
            Type targetContainingType,
            IEnumerable<CodeInstruction> instructions)
        {
            var field = AccessTools.Field(targetContainingType, targetFieldName);

            var matcher = new CodeMatcher(instructions);

            matcher.MatchStartForward(
                new CodeMatch(i => i.LoadsField(field))
            );

            if (!matcher.IsValid)
                return instructions;

            // Capture labels from the first instruction being removed
            var labels = matcher.Instruction.labels;

            // Move to next instruction AFTER the removed block
            matcher.Advance(2);

            // Reattach labels so branches still work
            matcher.Instruction.labels.AddRange(labels);

            // Go back and remove the original instructions
            matcher.Advance(-2);
            matcher.RemoveInstructions(2);

            return matcher.InstructionEnumeration();
        }
    }
}

#endif
