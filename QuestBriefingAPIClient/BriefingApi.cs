using System.IO;
using System.Reflection;

namespace Manimal.QuestBriefingAPI;

/// <summary>Register local quest recordings. Call from your plugin's Awake on the Unity main thread.</summary>
public static class BriefingApi
{
    internal static readonly BriefingRegistry Registry = new();

    /// <summary>Registers one recording. An existing quest registration wins; inspect the return value.</summary>
    /// <param name="ownerId">Unique mod/pack identifier, used in diagnostics and unregister calls.</param>
    /// <param name="questId">The quest's 24-character hexadecimal ID.</param>
    /// <param name="directory">Absolute local directory containing the recording.</param>
    /// <param name="fileName">Relative WAV/OGG/MP3 path, or extensionless stem (WAV, OGG, MP3 priority).</param>
    /// <param name="traderId">Optional trader restriction; null allows any trader.</param>
    /// <param name="radioFilter">False opts out of the user's radio filter. True/null follows user settings.</param>
    /// <param name="radioCues">False opts out of connection sounds. True/null follows user settings.</param>
    /// <returns>True if the recording was registered, false if it was already registered by another mod.</returns>
    public static bool Register(string ownerId, string questId, string directory, string fileName,
        string traderId = null, bool? radioFilter = null, bool? radioCues = null) =>
        Registry.Register(ownerId, questId, directory, fileName, traderId, radioFilter, radioCues);

    /// <summary>Registers one recording. An existing quest registration wins; inspect the return value.</summary>
    /// <param name="ownerId">Unique mod/pack identifier, used in diagnostics and unregister calls.</param>
    /// <param name="questId">The quest's 24-character hexadecimal ID.</param>
    /// <param name="assembly">The calling assembly, used to determine the mod folder location.</param>
    /// <param name="fileName">Relative WAV/OGG/MP3 path, or extensionless stem (WAV, OGG, MP3 priority).</param>
    /// <param name="traderId">Optional trader restriction; null allows any trader.</param>
    /// <param name="radioFilter">False opts out of the user's radio filter. True/null follows user settings.</param>
    /// <param name="radioCues">False opts out of connection sounds. True/null follows user settings.</param>
    /// <returns>True if the recording was registered, false if it was already registered by another mod.</returns>
    public static bool Register(string ownerId, string questId, Assembly assembly, string fileName, string traderId = null,
        bool? radioFilter = null, bool? radioCues = null) =>
        Registry.Register(ownerId, questId, Path.GetDirectoryName(assembly.Location), fileName, traderId, radioFilter, radioCues);
    
    /// <summary>Removes a recording only if it belongs to this owner. Reselect the quest to refresh its UI.</summary>
    public static bool Unregister(string ownerId, string questId) => Registry.Unregister(ownerId, questId);
}