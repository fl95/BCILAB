function check_shape(shape,value,argname)
% Check whether a given value can be assigned to a field of a given shape.
% check_type(ShapeString,Value,ArgumentName)
%
% This function throws an error message if the check fails.
%
% In:
%   ShapeString : a string that identifies the type of the argument (as in deduce_shape).
%
%   Value : the value to check
%
%   ArgumentName : name of the affected argument, for diagnostic messages.
%
%                                Christian Kothe, Swartz Center for Computational Neuroscience, UCSD
%                                2014-02-26

% Copyright (C) Christian Kothe, SCCN, 2014, christian@sccn.ucsd.edu
%
% This program is free software; you can redistribute it and/or modify it under the terms of the GNU
% General Public License as published by the Free Software Foundation; either version 2 of the
% License, or (at your option) any later version.
%
% This program is distributed in the hope that it will be useful, but WITHOUT ANY WARRANTY; without
% even the implied warranty of MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the GNU
% General Public License for more details.
%
% You should have received a copy of the GNU General Public License along with this program; if not,
% write to the Free Software Foundation, Inc., 59 Temple Place, Suite 330, Boston, MA  02111-1307
% USA

switch shape
    case 'scalar'
        if any(size(value) > 1)
            error('BCILAB:arg:shapecheck','The value assigned to %s (%s) must be scalar.',argname,hlp_tostring(value)); end
    case 'empty'
        if ~isempty(value)
            error('BCILAB:arg:shapecheck','The value assigned to %s (%s) must be empty.',argname,hlp_tostring(value)); end
    case 'row'
        if size(value,1) > 1
            error('BCILAB:arg:shapecheck','The value assigned to %s (%s) must be a row vector.',argname,hlp_tostring(value)); end
    case 'column'
        if size(value,2) > 1
            error('BCILAB:arg:shapecheck','The value assigned to %s (%s) must be a column vector.',argname,hlp_tostring(value)); end
    case 'matrix'
        if ndims(value) > 2
            error('BCILAB:arg:shapecheck','The value assigned to %s (%s) must be a matrix.',argname,hlp_tostring(value)); end        
end
