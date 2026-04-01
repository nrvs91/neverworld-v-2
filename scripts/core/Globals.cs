using Godot;
using System;

namespace Game.Core
{
    public partial class Globals : Node
    {

        public static Globals Instance { get; private set;}

        //[ExportCategory("Gameplay")]
        // how will we leverage this constant globals?
        // i presume it will be useful later?

        public override void _Ready()
    
        {
            Instance = this;
            Logger.Info("Loading Globals...");
        }
    }
}