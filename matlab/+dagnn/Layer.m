classdef Layer < handle
  %LAYER Base class for a network layer in a DagNN

  properties (SetAccess = {?dagnn.DagNN}, GetAccess = protected, Hidden, Transient)
    net
  end

  methods
    function outputs = forward(obj, inputs, params)
    %FORWARD Forward step
    %  OUTPUTS = FORWARD(OBJ, INPUTS, PARAMS) takes the layer object OBJ
    %  and cell arrays of inputs and parameters and produces a cell
    %  array of outputs evaluating the layer forward.
      outputs = {} ;
    end

    function [derInputs, derParams] = backward(obj, inputs, params, derOutpus)
    %BACKWARD  Bacwkard step
    %  [DERINPUTS, DERPARAMS] = BACKWARD(OBJ, INPUTS, INPUTS, PARAMS,
    %  DEROUTPUTS) takes the layer object OBJ and cell arrays of
    %  inputs, parameters, and output derivatives and produces cell
    %  arrays of input and parameter derivatives evaluating the layer
    %  backward.
      derInputs = {} ;
      derOutputs = {} ;
    end

    function reset(obj)
    %RESET Restore internal state
    %  RESET(OBJ) objets the layer objec OBJ, clearing any internal
    %  state.
    end

    function params = init(obj)
    %INIT Initialize layer parameters
    %  PARAMS = INIT(OBJ) takes the layer object OBJ and returns a cell
    %  array of layer parameters PARAMS with some initial
    %  (e.g. random) values.
      params = {} ;
    end

    function move(obj, device)
    %MOVE Move data to CPU or GPU
    %  MOVE(DESTINATION) moves the data associated to the layer object OBJ
    %  to either the 'gpu' or the 'cpu'. Note that variables and
    %  parameters are moved automatically by the DagNN object
    %  containing the layer, so this operation affects only data
    %  internal to the layer (e.g. the mask in dropout).
    end

    function forwardAdvanced(obj, layer)
    %FORWARDADVANCED  Advanced driver for forward computation
    %  FORWARDADVANCED(OBJ, LAYER) is the advanced interface to compute
    %  the forward step of the layer.
    %
    %  The advanced interface can be changed in order to extend DagNN
    %  non-trivially, or to optimise certain blocks.

      in = layer.inputIndexes ;
      out = layer.outputIndexes ;
      par = layer.paramIndexes ;
      net = obj.net ;

      % clear inputs if not needed anymore
      inputs = {net.vars(in).value} ;
      if ~net.computingDerivative & net.conserveMemory
        for v = in
          if net.vars(v).precious, continue ; end
          net.numPendingVarRefs(v) = net.numPendingVarRefs(v) - 1 ;
          if net.numPendingVarRefs(v) == 0, net.vars(v).value = [] ; end
        end
      end

      %[net.vars(out).value] = deal([]) ;

      outputs = obj.forward(inputs, {net.params(par).value}) ;
      [net.vars(out).value] = deal(outputs{:}) ;
    end

    function backwardAdvanced(obj, layer)
    %BACKWARDADVANCED Advanced driver for backward computation
    %  BACKWARDADVANCED(OBJ, LAYER) is the advanced interface to compute
    %  the backward step of the layer.
    %
    %  The advanced interface can be changed in order to extend DagNN
    %  non-trivially, or to optimise certain blocks.
      in = layer.inputIndexes ;
      out = layer.outputIndexes ;
      par = layer.paramIndexes ;
      net = obj.net ;

      inputs = {net.vars(in).value} ;
      derOutputs = {net.vars(out).der} ;
      for i = 1:numel(derOutputs)
        if isempty(derOutputs{i}), return ; end
      end

      if net.conserveMemory
        % clear output variables (value and derivative) unless precious
        for i = out
          if net.vars(i).precious, continue ; end
          net.vars(i).der = [] ;
          net.vars(i).value = [] ;
        end
      end

      % compute derivatives of inputs and paramerters
      [derInputs, derParams] = obj.backward ...
        (inputs, {net.params(par).value}, derOutputs) ;

      % accumuate derivatives
      for i = 1:numel(in)
        v = in(i) ;
        if net.numPendingVarRefs(v) == 0
          net.vars(v).der = derInputs{i} ;
        else
          net.vars(v).der = net.vars(v).der + derInputs{i} ;
        end
        net.numPendingVarRefs(v) == net.numPendingVarRefs(v) + 1 ;
      end

      for i = 1:numel(par)
        p = par(i) ;
        if isempty(net.params(p).der) || ~net.paramDersAccumulate
          net.params(p).der = derParams{i} ;
        else
          net.params(p).der = net.params(p).der + derParams{i} ;
        end
      end
    end

    function load(obj, varargin)
    %LOAD Initialize the layer from a paramter structure
    %  LOAD(OBJ, S) initializes the layer object OBJ from the parameter
    %  structure S.  It is the opposite of S = SAVE(OBJ).
    %
    %  LOAD(OBJ, OPT1, VAL1, OPT2, VAL2, ...) uses instead the
    %  option-value pairs to initialize the object properties.
    %
    %  LOAD(OBJ, {OPT1, VAL1, OPT2, VAL2, ...}) is an equivalent form
    %  to the previous call.
      if numel(varargin) == 1 && isstruct(varargin{1})
        s = varargin{1} ;
      else
        if numel(varargin) == 1 && iscell(varargin{1})
          args = varargin{1} ;
        else
          args = varargin ;
        end
        s = cell2struct(args(2:2:end),args(1:2:end),2) ;
      end
      for f = fieldnames(s)'
        f = char(f) ;
        obj.(f) = s.(f) ;
      end
    end

    function s = save(obj)
    %SAVE Save the layer configuration to a parameter structure
    %  S = SAVE(OBJ) extracts all the properties of the layer object OBJ
    %  as a structure S. It is the oppostie of LOAD(OBJ, S).
    %
    %  By default, properties that are marked as transient,
    %  dependent, abstract, or private in the layer object are not
    %  saved.
      s = struct ;
      m = metaclass(obj) ;
      for p = m.PropertyList'
        if p.Transient || p.Dependent || p.Abstract, continue ; end
        s.(p.Name) = obj.(p.Name) ;
      end
    end
  end
end
