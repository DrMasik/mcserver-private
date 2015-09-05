-------------------------------------------------------------------------------
-- Info.lua
-- Private
-------------------------------------------------------------------------------

g_PluginInfo = {
  Name = "Private",
  Version = "0",
  Date = "2015-08-31",
  Description = [[Private territory]],

  ConsoleCommands =
  {
    private_show_tmp_db =
    {
      HelpString = "debug for private",
      Handler = show_database,
    },
  },

  Commands = {
    ["/private"] = {
      HelpString = "Execute some of Private plugin commands",
      Permission = "private.core",

      Subcommands = {
        cancel = {
          HelpString = "Cancel active command",
          Handler = CommandCancel,
        },

        mark = {
          HelpString = "Begin markup territory",
          Handler = CommandMark,
          Permission = "private.mark"
        },

        list = {
          HelpString = "List user\'s privates",
          Handler = CommandList,
        },

        del = {
          HelpString = "Delete private territory",
          Handler = CommandDelete,
          ParameterCombinations = {
            Params = "name",
            HelpString = "Territory name",
          },
        },

        merge = {
          HelpString = "Merge two private territory",
          Handler = CommandMerge,
        },

        split = {
          HelpString = "Split into two parts",
          Handler = CommandSplit,
        },

        save = {
          HelpString = "Save market area",
          Handler = CommandSave,
          Permission = "private.save"
        },
      },
    },
  },

  ------------------------------------------------------------------------------------------
  -- Permissions section
  ------------------------------------------------------------------------------------------
  Permissions =
  {
  },
}

