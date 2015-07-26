function eval(obj, inputs, derOutputs)
% EVAL Evaluate the DAGNN
%   EVAL(obj, inputs) evaluates the DaG for the specified input
%   values. `inputs` is a cell array of the type `{'inputName',
%   inputValue, ...}`. This call results in a forward pass through the
%   graph, computing the values of the output variables. These can
%   then be accessed using the `obj.vars(outputIndex)` property of the
%   DaG object. The index of an output can be obtained using the
%   `obj.getOutputIndex(outputName)` call.
%
%   EVAL(obj, inputs, derOutputs) evaluates the DaG forward and then
%   backward, performing backpropagation. Similar to `inputs`,
%   `derOutputs` is a cell array of the type {'outputName',
%   outputDerValue, ...} of output derivatives.
%
%   # Understanding backpropagation
%
%   Only those outputs for which an `outputDerValue` which is
%   non-empty are involved in backpropagation, while the others are
%   ignored. This is useful to attach to the graph auxiliary layers to
%   compute errors or other statistics, without however involving them
%   in backpropagation.
%
%   Usually one starts backpropagation from scalar outptus,
%   corresponding to loss functions. In this case `outputDerValue` can
%   be interpreted as the weight of that output and is usually set to
%   one. For example: `{'objective', 1}` backpropagates from the
%   `'objective'` output variable with a weight of 1.
%
%   However, in some cases the DaG may contain more than one such
%   node, for example because one has more than one loss function.  In
%   this case `{'objective1', w1, 'objective2', w2, ...}` allows to
%   balance the different objectives.
%
%   Finally, one can backpropagate from outputs that are *not*
%   scalars. While this is unusual, it is possible by specifying a
%   value of `outputDerValue` that has the same dimensionality as the
%   output; in this case, this value is used as a matrix of weights,
%   or projection.
%
%   # Factors affecting evaluation
%
%   There are several factors affecting evaluation:
%
%   * The *evaluation mode* can be either `train` or `test`. Layers
%     may behave differently depending on the mode. For example, dropout
%     becomes a pass-through layer in test mode (this usually improves
%     the test performance significantly).
%
%   * By default, the DaG aggressively conserves memory. This is
%     particularly important on the GPU, where memory is
%     scarce. However, this also means that the values of most
%     variables and of their derivatives are dropped during the
%     computation. For debugging purposes, it may be interesting to
%     observe these variables; in this case you can set the
%     `obj.conserveMemory` property of the DaG to `false`. It is also
%     possible to preserve individual variables by setting the
%     property `obj.vars(v).precious` to `true`.

% Copyright (C) 2015 Andrea Vedaldi.
% All rights reserved.
%
% This file is part of the VLFeat library and is made available under
% the terms of the BSD license (see the COPYING file).

obj.computingDerivative = nargin > 2 && ~isempty(derOutputs) ;

% -------------------------------------------------------------------------
% Forward pass
% -------------------------------------------------------------------------

% set the input values
for i = 1:2:numel(inputs)
  v = obj.getVarIndex(inputs{i}) ;
  switch obj.device
    case 'cpu', obj.vars(v).value = gather(inputs{i+1}) ;
    case 'gpu', obj.vars(v).value = gpuArray(inputs{i+1}) ;
  end
end
inputs = [] ;

obj.numPendingVarRefs = [obj.vars.fanout] ;
for l = 1:numel(obj.layers)
  time = tic ;
  obj.layers(l).block.forwardAdvanced(obj.layers(l)) ;
  obj.layers(l).forwardTime = toc(time) ;
end

% -------------------------------------------------------------------------
% Backward pass
% -------------------------------------------------------------------------

if ~obj.computingDerivative, return ; end

% set output derivatives
v = obj.getVarIndex(derOutputs(1:2:end)) ;
[obj.vars(v).der] = deal(derOutputs{2:2:end}) ;
derOutputs = [] ;

obj.numPendingVarRefs = zeros(1, numel(obj.vars)) ;
for l = numel(obj.layers):-1:1
  time = tic ;
  obj.layers(l).block.backwardAdvanced(obj.layers(l)) ;
  obj.layers(l).backwardTime = toc(time) ;
end
