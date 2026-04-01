using Godot;
using System;

namespace Game.Core
{
	public static class Logger
	{
		public static void Log(string level, params object[] message)
		{
			var dateTime = DateTime.Now;
			string timeStamp = $"[{dateTime:yyyy-MM-dd HH:mm:ss}]";
			var callingMethod = new System.Diagnostics.StackTrace().GetFrame(2).GetMethod();
			string logMessage = $"{timeStamp} [{level}] [{callingMethod.DeclaringType.Name}] [{callingMethod.Name}]";
			GD.Print([logMessage, ..message]);
		}
		public static void Debug(params object[] message)
		{
			Log("DEBUG", message);
		}

		public static void Info(params object[] message)
		{
			Log("INFO", message);
		}

		public static void Warn(params object[] message)
		{
			Log("WARNING", message);
		}
		public static void Error(params object[] message)
		{
			Log("ERROR", message);
		}
	}
}

