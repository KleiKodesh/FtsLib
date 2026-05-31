namespace FstLib.Core
{
    /// <summary>
    /// Specifies how string keys are encoded into arc labels during FST construction.
    /// The numeric value equals the number of bytes per label.
    /// </summary>
    public enum InputType : byte
    {
        /// <summary>UTF-8 encoding — one byte per label (ASCII-range keys only).</summary>
        BYTE1 = 1,
        /// <summary>UTF-16 encoding — two bytes per label (full BMP coverage).</summary>
        BYTE2 = 2,
        /// <summary>UTF-32 encoding — four bytes per label (full Unicode coverage).</summary>
        BYTE4 = 4
    }
}
