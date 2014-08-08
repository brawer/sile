SILE.Commands = {}
SILE.Help = {}
function SILE.registerCommand (name, f, help, pack) 
  SILE.Commands[name] = f 
  if not pack then
    local where = debug.getinfo(2).source
    pack = where:match("(%w+).lua")
  end
  --if not help and not pack:match(".sil") then SU.error("Could not define command '"..name.."' (in package "..pack..") - no help text" ) end

  SILE.Help[name] = {
    description = help,
    where = pack
  }
end

SILE.baseClass = std.object {
  registerCommands = (function()
    SILE.registerCommand("\\", function(o,c)  SILE.typesetter:typeset("\\") end)

    local commandStack = {};
    SILE.registerCommand("define", function (options, content)
      SILE.registerCommand(options["command"], function(o,c)
        --local prevState = SILE.documentState;
        --SILE.documentState = std.tree.clone( prevState )
        table.insert(commandStack, c)
        SILE.process(content)
        --SILE.documentState = prevState
      end, options.help, SILE.currentlyProcessingFile)
    end, "Define a new macro. \\define[command=example]{ ... \\process }")

    SILE.registerCommand("comment", function(o,c) end, "Ignores any text within this command's body.");
    SILE.registerCommand("process", function()
      SILE.process(table.remove(commandStack));
    end, "Within a macro definition, processes the contents of the macro body.")

    SILE.registerCommand("script", function(options, content)
      if (options["src"]) then 
        require(options["src"])
      else 
        p,e = loadstring(content[1])
        if not p then SU.error(e) end
        p()
      end
    end, "Runs lua code. The code may be supplied either inline or using the src=... option. (Think HTML.)")

    SILE.registerCommand("include", function(options, content)
        SILE.readFile(options["src"]);
    end, "Includes a SILE file for processing.")

    SILE.registerCommand("pagetemplate", function (options, content) 
      SILE.documentState.thisPageTemplate = { frames = {} };
      SILE.process(content);
      SILE.documentState.thisPageTemplate.firstContentFrame = SILE.getFrame(options["first-content-frame"]);
      SILE.typesetter:initFrame(SILE.documentState.thisPageTemplate.firstContentFrame);
    end, "Defines a new page template for the current page and sets the typesetter to use it.")

    SILE.registerCommand("frame", function (options, content)
      local spec = {
        id = options.id,
        next = options.next,
        balanced = (options.balanced or 0),
        top = options.top and function() return SILE.parseComplexFrameDimension(options.top, "h") end,
        bottom = options.bottom and function() return SILE.parseComplexFrameDimension(options.bottom, "h") end,
        left = options.left and function() return SILE.parseComplexFrameDimension(options.left, "w") end,
        right = options.right and function() return SILE.parseComplexFrameDimension(options.right, "w") end,
        width = options.width and function() return SILE.parseComplexFrameDimension(options.width, "w") end,
        height = options.height and function() return SILE.parseComplexFrameDimension(options.height, "h") end,
      };
      SILE.documentState.thisPageTemplate.frames[options.id] = SILE.newFrame(spec);
    end, "Declares (or re-declares) a frame on this page.")

    SILE.registerCommand("penalty", function(options, content)
      if (SILE.typesetter:vmode()) then
        SILE.typesetter:pushVpenalty({ flagged= tonumber(options.flagged), penalty = tonumber(options.penalty) })
      else
        SILE.typesetter:pushPenalty({ flagged= tonumber(options.flagged), penalty = tonumber(options.penalty) })
      end
    end, "Inserts a penalty node. Options are penalty= for the size of the penalty and flagged= if this is a flagged penalty.")

    SILE.registerCommand("glue", function(options, content) 
      SILE.typesetter:pushGlue({ 
        width = SILE.length.parse(options.width)
      })
    end, "Inserts a glue node. The width option denotes the glue dimension.")

    SILE.registerCommand("skip", function(options, content)
      SILE.typesetter:leaveHmode();
      SILE.typesetter:pushVglue({ height = SILE.length.parse(options.height) })
    end, "Inserts vertical skip. The height options denotes the skip dimension.")

    SILE.registerCommand("par", function(options, content) 
      SILE.typesetter:leaveHmode()
    end, "Ends the current paragraph.")

  end),

  pageTemplate = std.object { frames= {}, firstContentFrame= nil },
  loadPackage = function(self, packname, args)
    local pack = require("packages/"..packname)
    if type(pack) == "table" then 
      self:mapfields(pack.exports)
      if pack.init then
        pack.init(self, args)
      end
    end
  end,
  init = function(self)
    SILE.settings.declare({
      name = "current.parindent",
      type = "Glue",
      default = SILE.settings.get("document.parindent"),
      help = "Glue at start of paragraph"
    })
    SILE.outputter.init(self); 
    self:registerCommands();
    return self:initialFrame();
  end,
  initialFrame= function(self)
    SILE.documentState.thisPageTemplate = std.tree.clone(self.pageTemplate)
    local p = SILE.frames.page
    SILE.frames = {page = p}
    for k,v in pairs(SILE.documentState.thisPageTemplate.frames) do
      SILE.frames[k] = v
    end
    SILE.documentState.thisPageTemplate.firstContentFrame:invalidate()
    return SILE.documentState.thisPageTemplate.firstContentFrame
  end,
  declareFrame = function (self, id, spec)
    -- local fW = function (val) return function() return SILE.parseComplexFrameDimension(val, "w"); end end
    -- local fH = function (val) return function() return SILE.parseComplexFrameDimension(val, "h"); end end
    spec.id = id
    self.pageTemplate.frames[id] = SILE.newFrame(spec)
    --   next= spec.next,
    --   left= spec.left and fW(spec.left),
    --   right= spec.right and fW(spec.right),
    --   top= spec.top and fH(spec.top),
    --   bottom= spec.bottom and fH(spec.bottom),
    --   height = spec.height and fH(spec.height),
    --   width = spec.width and fH(spec.width),
    --   id = id
    -- });
  end,
  newPage = function(self) 
    SILE.outputter:newPage();
    -- Any other output-routiney things will be done here by inheritors
    return self:initialFrame();
  end,
  endPage= function()
    SILE.typesetter:leaveHmode();
    -- Any other output-routiney things will be done here by inheritors
  end,
  finish = function(self)
    self:endPage();
    SILE.typesetter:chuck()
 end,
  newPar = function(typesetter)
    typesetter:pushVglue(SILE.settings.get("document.lineskip"))
    typesetter:pushGlue(SILE.settings.get("current.parindent"))
    SILE.settings.set("current.parindent", SILE.settings.get("document.parindent"))    
  end,
  options= { 
    papersize= function(size)
      _, _, x, y = string.find(size, "(.+)%s+x%s+(.+)")
      if x then
        SILE.documentState.paperSize ={ SILE.toPoints(x), SILE.toPoints(y) };
      elseif (SILE.paperSizes[size]) then
        SILE.documentState.paperSize = SILE.paperSizes[size];
      else
        SU.error("Unknown paper size "..size);
      end
      SILE.newFrame({id = "page", left = 0, top = 0, right = SILE.documentState.paperSize[1], bottom = SILE.documentState.paperSize[2] })
    end
  }
}