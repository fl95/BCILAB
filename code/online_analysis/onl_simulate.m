function [predictions,predict_at,timings] = onl_simulate(varargin)
% Apply a predictive model to some raw data set at specified time points.
% [Predictions,Latencies,TImings] = onl_simulate(Data,Model,Markers,Latencies,SamplingRate,Shift,Format,Interval,Waitbar,Feedback)
% 
% 
% The function onl_simulate is the standard way in BCILAB to apply predictive models to data sets,
% i.e. to receive predictions of cognitive state at various specified time points in the given data
% set. The data set must be unfiltered, but it may have been structurally edited (e.g. chanlocs,
% dipfit, etc.), The model is usually one that has been previously computed using bci_train (see
% bci_train) on some calibration data set (note that predictions on the calibration data set itself
% result in overly optimistic estimates, and are usually scientifically invalid results).
% 
% The time points at which the model shall be invoked can be specified in flexible ways: among
% others, a model can be invoked at certain specified latencies ('Samples'), at a given rate
% ('SamplingRate'), or relative to events of certain types ('Markers'). Generally, a constant offset
% can be added to the specified time points, which is important when classifying relative to certain
% stimulus events: usually the data necessary for the prediction is only fully available at some
% time after the stimulus event (as a rule of thumb: when a model was calibrated relative to events,
% using an epoch clause which ended x seconds past the event, then this is the amount of time that
% needs to be specified as the offset (converted in samples).
% 
% The predictions produced by onl_simulate are of the same format as those produced by bci_predict
% and ml_predict (and may depend on how the model was calibrated), see bci_predict for an
% explanation of the most common case(s).
%
% onl_predict uses the online infrastructure of the toolbox to produce its results (and can
% currently not be used while online processing is in progress in the current MATLAB instance).
% Therefore, the outputs are exactly identical to what would be computed by the model if it was
% applied in real time. The analysis done by onl_simulate is typically called "pseudo-online
% analysis", since the data is actually streamed (causally) through the processing chain in a
% simulated online fashion. In contrast, the related bci_predict does what is often called "offline
% analysis", in which the data is processed not necessarily causally in successive stages, and
% predictions are obtained in a trial-by-trial fashion, not in a time-point-by-time-point fashion;
% offline analysis typically involves known desired outputs, against which the predictions of the
% model are compared, to get loss estimates. The framework of bci_predict is designed to give
% identical results to what would be computed by onl_simulate in the respective situations (e.g. at
% the time points of certain events), but the data processing is generally more efficient (for
% example, intermediate results can be cached in memory or on disk, whereas onl_simulate usually
% processes the data in small chunks). For these reasons, onl_simulate is the preferred method when
% details of the time course of a model's output are required (e.g. how it behaves in the proximity
% of events or in areas of the data where unknown cognitive processes take place), and/or when it
% must be 100% certain that the model can be applied online as-is. bci_predict is the preferred
% method when high-throughput offline analyses on certain constrained portions of the data (e.g.
% relative to events) need to be executed as efficiently as possible (e.g. in batch analyses).
%
%
% In:
%   Data         : raw EEGLAB data set that shall be streamed through the online pipeline,
%                  or stream bundle, or cell array of EEGLAB data sets
%
%   Model        : the predictive model (as produced by bci_train) that should be used to make
%                  predictions at certain latencies in the data (specified in the Options)
%
%   UpdateRate   : predict at the given sampling rate (in Hz)
%
%   Latencies    : predict at the given data sample latencies (if multiple streams are passed this is 
%                  measured by the rate of the first stream)
%
%   Markers      : predict when an event appears whose type matches any of the markers
%
%   Shift        : add this offset (in seconds) to the times at which the predictive model is invoked 
%
%   TargetMarkers: Target markers for prediction. If non-empty, predictions will only be generated per 
%                  each target marker; if empty, a prediction will be generated for each sample where 
%                  onl_predict is called. (default: {})
%
%   Format       : format of the prediction; see utl_formatprediction (default: 'distribution')
%
%   Interval     : process only this interval of the data, in seconds (if both ends <= 1, assume
%                  that the interval is a fraction) (default: [0 1])
%   
%   Waitbar      : whether to display a progress update (default: 0) 
%   
%   Feedback     : whether to display a bar diagram for every prediction (default: 0)
%
%   TightenBuffer: whether to tighten the stream buffer for increased speed (default: false)
%                  note: if this is true, the resulting processing times are not representative of
%                        actual online processing speed
%
%   Verbose      : Verbose output. If false, the console output of the online pipeline will be suppressed.
%                  (default: false)
%
%   ForceArrayOutputs : Force outputs into array. If true, the predictions, which would normally be a cell array, 
%                       are returned as a numeric array. If no target markers are specified then all predictions that 
%                       yielded no results are replaced by appropriately-sized NaN vectors. (default: true)
%
% Out:
%   Predictions : the prediction results for every point at which the detector should be invoked
%
%   Latencies   : data set points for the corresponding predictions (in seconds)
%
% Notes:
%   NaN outputs are generated at time points where no prediction could be made (e.g. too close to data 
%   set boundaries).
%
% Examples:
%  % 1. load calibration data and compute a model (see bci_train)
%  calib = io_loadset('data sets/mary/stresslevels_calib.set');
%  [loss,model] = bci_train({'data',calib,'paradigm',@para_speccsp},'events',{'low','medium','high'});
%
%  % 2. apply pseudo-online, here at a rate of 5 Hz
%  testdata = io_loadset('data sets/mary/stresslevels_realworld.set');
%  [predictions,latencies] = onl_simulate(testdata, model, 'SamplingRate',5);
%
%  % 3. plot time course of the model's output
%  plot(latencies, predictions{2}*predictions{3}); title('expected stress level');
%
% See also:
%   bci_anntate, onl_predict
%
%                                Christian Kothe, Swartz Center for Computational Neuroscience, UCSD
%                                2010-11-07

arg_define([0 2],varargin, ...
    arg_norep({'signal','Data','Signal'}), ...
    arg_norep({'mdl','Model'}), ...
    arg({'sampling_rate','UpdateRate','update_rate','SamplingRate'},[],[0 Inf],'Predict at this rate. If set, produce outputs at the given sampling rate.'), ...
    arg({'locksamples','Latencies'}, [], [], 'Predict at these latencies. Produce outputs at the given data sample latencies.','shape','row'), ...
    arg({'lockmrks','Markers','markers'}, {}, [], 'Predict at these events. Produce outputs at the latencies of these events.','type','expression'), ...
    arg({'relshift','Shift','offset'},0,[],'Add time offset. Shift the time points at which to predict by this amount (in seconds).'), ...
    arg({'target_markers','TargetMarkers'},{},[],'Target markers for prediction. If non-empty, predictions will only be generated per each target marker; if empty, a prediction will be generated for each sample where onl_predict is called.','type','expression'), ...
    arg({'outformat','Format','format'},'distribution',{'expectation','distribution','mode'},'Prediction format. See utl_formatprediction.'), ...
    arg({'dowaitbar','Waitbar'},false,[],'Display progress update. A waitbar will be displayed if enabled.'), ...
    arg({'dofeedback','Feedback'},false,[],'Display BCI outputs. BCI outputs will be displayed on the fly if enabled.'), ...
    arg({'restrict_to','Interval','interval'},[0 1],[0 Inf],'Restrict to time interval. Process only this interval of the data, in seconds (if both ends <= 1, assume that the interval is a fraction)'), ...
    arg({'tighten_buffer','TightenBuffer'},false,[],'Tighten data buffer. Optional speed optimization that is specific to offline simulation.'), ...
    arg({'verbose_output','Verbose','verbose'}, false,[],'Verbose output. If false, the console output of the online pipeline will be suppressed.'), ...
    arg({'force_array','ForceArrayOutputs'},true,[],'Force outputs into array. If true, the predictions, which would normally be a cell array, are returned as a numeric array. If no target markers are specified then all predictions that yielded xno results are replaced by appropriately-sized NaN vectors.'));

% uniformize the data
if all(isfield(signal,{'data','srate'}))
    signal = struct('streams',{{signal}}); end
if iscell(signal)
    signal = struct('streams',{signal}); end

% and make sure that it is well-formed and evaluated
signal = utl_check_bundle(signal);
for s=1:length(signal.streams)
    signal.streams{s} = exp_eval_optimized(signal.streams{s}); end

% we use the sampling rate and bounds of the first stream to determine the prediction points
stream_srate = signal.streams{1}.srate;
stream_xmax = signal.streams{1}.xmax;
if all(restrict_to <= 1)
    restrict_to = max(0,min(1,restrict_to)) * stream_xmax;
else
    restrict_to = max(0,min(stream_xmax,restrict_to));
end

% aggregate the time points at which the model should be invoked
predict_at = [];
for m=1:length(lockmrks)
    predict_at = [predict_at ([signal.streams{1}.event(strcmp(lockmrks{m},{signal.streams{1}.event.type})).latency]-1)/stream_srate]; end
if ~isempty(sampling_rate)
    predict_at = [predict_at 0:(1/sampling_rate):stream_xmax]; end
if ~isempty(locksamples)
    predict_at = [predict_at locksamples/stream_srate]; end
predict_at = predict_at + relshift;
predict_at = predict_at(predict_at >= restrict_to(1) & predict_at <= restrict_to(2));
predict_at = sort(predict_at);
predictions = cell(1,length(predict_at));

% optionally clear any existing target markers in the given streams
if ~isempty(target_markers)
    for s=1:length(signal.streams)
        if ~isempty(signal.streams{s}.event)
            [signal.streams{s}.event.target] = deal([]); end
    end
end

% initialize the online stream(s)
stream_names = {};
for s=1:length(signal.streams)
    stream_names{s} = sprintf('stream_simulated_%.0f',s);
    if tighten_buffer
        onl_newstream(stream_names{s}, signal.streams{s}, 'buffer_len',max(diff(predict_at)) + 10/signal.streams{s}.srate);
    else
        onl_newstream(stream_names{s}, signal.streams{s});
    end
end

onl_newpredictor('predictor_simulated',mdl,stream_names,target_markers);

% init BCI display
if dofeedback
    figure; drawnow; end

% get the latencies of events in each stream
for s=length(signal.streams):-1:1
    event_latencies{s} = round([signal.streams{s}.event.latency]);  end

% for each latency of interest...
cursors = zeros(1,length(signal.streams)); % signal up to an including this sample latency has been streamed in
timings = zeros(1,length(predict_at));
for k=1:length(predict_at)    
    t0 = tic;
    
    % skip ahead to the position of the next prediction
    % (i.e. feed all samples and markers from the current cursor up to that position)
    for s=1:length(signal.streams)
        next_sample = 1 + round(predict_at(k)*signal.streams{s}.srate);
        range = (cursors(s)+1) : next_sample;
        events = signal.streams{s}.event(event_latencies{s}>=range(1)&event_latencies{s}<=range(end));
        if ~isempty(events)
            [events.latency] = arraydeal([events.latency]-range(1)+1);end
        onl_append(stream_names{s},signal.streams{s}.data(:,range),events);
        cursors(s) = next_sample;
    end
    
    % query the predictor
    predictions{k} = onl_predict('predictor_simulated',outformat,verbose_output,[]);
    
    timings(k) = toc(t0);
    % display outputs
    if dowaitbar && mod(k,floor(length(predict_at)/100))==0
        waitbar(k/length(predict_at),'Processing...'); end        
    if dofeedback && ~any(isnan(predictions{k}))
        bar(predictions{k}); ylim([0 1]);
        drawnow; 
    end
end

if force_array
    if isempty(target_markers)
        % insert NaN's for empty predictions
        dims = cellfun('size',predictions,2);
        [predictions{~dims}] = deal(nan(1,median(dims(logical(dims)))));
    end
    predictions = vertcat(predictions{:});        
end
