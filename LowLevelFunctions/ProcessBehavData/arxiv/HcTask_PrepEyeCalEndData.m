 function [MLStruct] = HcTask_PrepEyeCalEndData(SessionDir, CalOrEnd)
%% Extract session and trial information

% Defines Slash for separating folders
if ispc
    Slash = '\';
else
    Slash = '/';
end

%Selects all files to open
Contents = dir(SessionDir);

%We need to sort the files in their date order because by default the
%algorithm sorts them like: Trial1, Trial10, Trial11,... Trial2, Trial
%20,....

[~ , Order] = sort([Contents.datenum]);
Contents = Contents(Order);

ValidTrials = {Contents(cell2mat(cellfun(@(x) (~isempty(x)), (strfind({Contents.name}, 'Trial')), 'uni', false))).name};
EDFFile = {Contents(cell2mat(cellfun(@(x) (~isempty(x)), (strfind({Contents.name}, 'edf')), 'uni', false))).name};

%% Extract session and trial information
hWaitBar = waitbar(0, ['Going through Eye' CalOrEnd ' trials.']);

%Changes added do address the fact that Monkey lab used to do smoothing 

% load the EDF file that has the eye samples for the whole session
edfEyeSamplefile = edfmex(char([SessionDir Slash EDFFile{1}] ));
StartIndexEyeSamples = 1;

%Load all trials
for trl = 1:numel(ValidTrials)
    tic
    
    % Initialize dynamic variables
    eventsNumber        = [];
    Sys_SetupID         = 00;  %Need setup id for eye calibration data
    Ses_MonkeyName      = 'Default Monkey';
    Ses_Date            = '01-Jan-0000';
    Trl_TrialID         = '000000000000000';
    Trl_SOT             = 0;
    Trl_EOT             = 0;
    Trl_StartEDF        = 0;
    Trl_EOTEDF          = 0;
    Trl_Outcome         = '';
    Sync_ITC18StartTime = 0;
    Sync_Pulse          = []; % Columns 1 - 2: Pulse Time
    Eye_FixPoint        = [];
    Eye_FixPointOnset   = [];
    Eye_FixPointOffset  = [];
    Eye_EDFtimeDiff     = []; %stores the difference between the Eyelink and Monkeylab time
    Eye_Samples         = []; % Columns 1 - 3: EyeX EyeY MonkeyLab_Time, taken from EDF file
    Eye_SamplesBad         = []; % Columns 1 - 3: EyeX EyeY MonkeyLab_Time, smoothed
    Eye_Calibration     = []; % Columns 1 - 3: GainX GainY Offset; Rows 1 - 2: EyeX EyeY
    Eye_ScreenHeight    = [];
    Eye_ScreenWidth     = [];
    Eye_ScreenDistance  = [];
    %% Load the EyeData from the EDF
    % the smaples are in FSamples, but the events are in FEvent. For each
    % trial, the name has to be gotten, 
    
    % Load the event data for the trial.
    events = cell(1,1);  %Need to predefine the variable to remove conflict with events function
    
    % Concatenates file path with file name, no need to change cd.
    load(char([SessionDir Slash ValidTrials{trl}] ));
    eventsNumber = length(events);
    
    for k = 1:eventsNumber
        
        % Separates data according to event type
        switch events{k}.name
            
            case 'sendTrialID'
                EDFtrialStart = events{k}.time;
            case 'savingController::taskDialog' % (1) ---------------------
                
                % Create trlParams variable, which contains :
                % Vseparation, HSeparation, BGintensity, fixHold,
                % fixWindow, autoreward, colorflicker, fixpointsize
                Params.VSeparation = events{k}.VSeparation;
                Params.HSeparation = events{k}.HSeparation;
                Params.BGIntensity = events{k}.BGIntensity;
                Params.fixHold = events{k}.fixHold;
                Params.fixWindow = events{k}.fixWindow;
                Params.ColorFlicker = events{k}.ColorFlicker;
                Params.FixPtSize = events{k}.FixPtSize;
                
                
            case 'currentFixPoint'              % (2) ---------------------
                
                Eye_FixPoint = [events{k}.xDeg events{k}.yDeg];
                
                
            case 'showFixationPoint'            % (3) ---------------------
                
                Eye_FixPointOnset = events{k}.time;
                
                
            case 'hideFixationPoint'            % (4) ---------------------
                
                Eye_FixPointOffset = events{k}.time;
                
                
            case 'eyeSample'                    % (5) ---------------------
                
                % Since eye samples are sent one at a time, we do not need
                % to convert time to ML, we already have it.
                
                
                % File should have a sampleTimeSecs field that time stamps
                % the time at which the sample is taken and not when the
                % event is sent (time). However some older files might not
                % have it, so need to check.
                if isfield(events{k}, 'sampleTimeSecs')
                    Eye_SamplesBad = [Eye_SamplesBad; double(events{k}.eyeUnits) double(events{k}.sampleTimeSecs)];
                    Eye_EDFtimeDiff = [Eye_EDFtimeDiff; double(events{k}.sampleTimeSecs) - ...
                        double(events{k}.eyeLinkSampleTime)*.001];
                else %if not, then use time. CAREFUL: there might be a delay between sampleTimeSecs and time.
                    Eye_SamplesBad = [Eye_SamplesBad; double(events{k}.eyeUnits) double(events{k}.time)];
                    Eye_EDFtimeDiff = [Eye_EDFtimeDiff; double(events{k}.time) - ...
                        double(events{k}.eyeLinkSampleTime)*.001];
                end
                
                %Removed because of conflicting information between
                %eyeCalibration and savingController::eyeDialog. Probably
                %because the eyeCalibration event doesn't take into account
                %last eye calibration trial.
                %             case 'eyeCalibration'               % (6) ---------------------
                
                % Gets the info from the EyeCalibration Event
                % We only get how to convert the units to degrees, we will
                % need further processing to convert to pixels.
                %                 Eye_Calibration = events{k}.units2Deg;
                %                 QuadrantCorrect = events{k}.QuadrantCorrect;
                
                
            case 'savingController::eyeDialog'  % (7) ---------------------
                
                % The eye calibration data might also be found in the
                % saving of the eyeDialog window.
                Eye_Calibration(1,1) = events{k}.a;
                Eye_Calibration(1,2) = events{k}.b;
                Eye_Calibration(1,3) = events{k}.c;
                Eye_Calibration(1,4) = events{k}.d;
                Eye_Calibration(1,5) = events{k}.e;
                
                Eye_Calibration(2,1) = events{k}.f;
                Eye_Calibration(2,2) = events{k}.g;
                Eye_Calibration(2,3) = events{k}.h;
                Eye_Calibration(2,4) = events{k}.i;
                Eye_Calibration(2,5) = events{k}.j;
                
                QuadrantCorrect(1,1) = events{k}.m_1;
                QuadrantCorrect(1,2) = events{k}.m_2;
                QuadrantCorrect(1,3) = events{k}.m_3;
                QuadrantCorrect(1,4) = events{k}.m_4;
                
                QuadrantCorrect(2,1) = events{k}.n_1;
                QuadrantCorrect(2,2) = events{k}.n_2;
                QuadrantCorrect(2,3) = events{k}.n_3;
                QuadrantCorrect(2,4) = events{k}.n_4;
                
            case 'savingController::screenDialog'  % (7) ---------------------
                
                Eye_ScreenHeight    = events{k}.screenHeightCM*2;
                Eye_ScreenWidth     = events{k}.screenWidthCM*2;
                Eye_ScreenDistance  = events{k}.screenDistanceCM;
                
            case 'endOfTrial'                   % (8) ---------------------
                
                % Get Trial outcome
                Trl_Outcome = events{k}.eot;
                
                % Get End of trial time
                Trl_EOT = events{k}.time;
                
                % Get the end of trial time in EyeLink time
%                 Trl_EOTEDF = events{k}.
                
            case 'startOfTrial'                 % (9) ---------------------
                
                % Get Setup ID from trial ID;
                % Trial ID  = DDD DSS SSS ssT TTT
                %   D = Days since Jan 1 2012
                %   S = Seconds of day
                %   s = setup ID
                %   T = Trial number
                Trl_TrialID = events{k}.trialID;
                Sys_SetupID = Trl_TrialID(10:11);  % 01 = Cerebus, 02 = Plexon
                
                %Get Start of trial Time
                Trl_SOT = events{k}.time;
                
                % Get Monkey Name
                Ses_MonkeyName = events{k}.MonkeyName;
                
                % Get Session date
                Ses_Date = events{k}.date;
                
                
            case 'SyncPulseRead'                % (10) --------------------
                
                % =========================================================
                % Changed the event name to SyncPulseRead and the field
                % name to SyncPulse because it was not reading it properly.
                % =========================================================
                
                % Get Pulse points
                tempPulse = double(events{k}.SyncPulse);
                tempPulseTime = zeros(size(tempPulse,1), size(tempPulse,2));
                
                % Validate that we have data
                if ~isempty(tempPulse)
                    tempPulseTime(1, size(tempPulse,2)) = events{k}.time;
                    
                    % Add Data to variable
                    Sync_Pulse = double([Sync_Pulse; tempPulse' tempPulseTime']);
                    
                end
                
                
            case 'ITC18TimeZero'                % (11)---------------------
                
                % Get ITC 18 start collection time
                Sync_ITC18StartTime = events{k}.time;
        end
        
    end
    
    %get the average difference between monkeylab and eyelink time
   
   
    edfDiff = Eye_EDFtimeDiff-Eye_EDFtimeDiff(1);
   
    % Find the time eyelink time that aligns with the start of the trial
    % (the end of the last trial) and the end of this trial. get the
    % indices of these times, and then get the eye samples for these
    % periods
     Trl_EOTEDF = find(edfEyeSamplefile.FSAMPLE.time<(Trl_EOT-Eye_EDFtimeDiff(1))*1000,1,'last');
    Eye_Samples = [double(edfEyeSamplefile.FSAMPLE.hx(1,StartIndexEyeSamples:Trl_EOTEDF))' ...
        double(edfEyeSamplefile.FSAMPLE.hy(1,StartIndexEyeSamples:Trl_EOTEDF))'...
        double(edfEyeSamplefile.FSAMPLE.time(StartIndexEyeSamples:Trl_EOTEDF))'*.001+Eye_EDFtimeDiff(1)...
                double(edfEyeSamplefile.FSAMPLE.pa(1,StartIndexEyeSamples:Trl_EOTEDF))']; 
            StartIndexEyeSamples = Trl_EOTEDF+1;
    if ~strcmp(Trl_TrialID,'000000000000000')
        
        % Session-specific information
        MLStruct.SessionInfo.MonkeyName      = Ses_MonkeyName;      %
        MLStruct.SessionInfo.Date            = Ses_Date;            %
        MLStruct.SessionInfo.SetupID         = Sys_SetupID;         %
        
        %If no eye calibration in last trial, use the last valid values
        if ~isempty(Eye_Calibration)
            MLStruct.SessionInfo.EyeCalibration  = Eye_Calibration;     %
            MLStruct.SessionInfo.QuadrantCorrect = QuadrantCorrect;     %
        end

        MLStruct.SessionInfo.Params          = Params;              %
        MLStruct.SessionInfo.ScreenHeight    = Eye_ScreenHeight;
        MLStruct.SessionInfo.ScreenWidth     = Eye_ScreenWidth;
        MLStruct.SessionInfo.ScreenDistance  = Eye_ScreenDistance;
        
        % Trial-specific information
        MLStruct.Trials.(['ID_' Trl_TrialID]).CurrentFixPoint= Eye_FixPoint;        %
        MLStruct.Trials.(['ID_' Trl_TrialID]).FixPointOnset  = Eye_FixPointOnset;   %
        MLStruct.Trials.(['ID_' Trl_TrialID]).FixPointOffset = Eye_FixPointOffset;  %
        MLStruct.Trials.(['ID_' Trl_TrialID]).OutcomeWord    = Trl_Outcome;         % (7) Change this to be 'Completed' rather than 'Correct'
        MLStruct.Trials.(['ID_' Trl_TrialID]).EyeSamplesBad     = Eye_SamplesBad;         %
        MLStruct.Trials.(['ID_' Trl_TrialID]).EyeSamples     = Eye_Samples;         %
        MLStruct.Trials.(['ID_' Trl_TrialID]).ITC18StartTime = Sync_ITC18StartTime; % (10)
        MLStruct.Trials.(['ID_' Trl_TrialID]).SOT_Time       = Trl_SOT;             % (6)
        MLStruct.Trials.(['ID_' Trl_TrialID]).EOT_Time       = Trl_EOT;             % (7)
        MLStruct.Trials.(['ID_' Trl_TrialID]).SyncPulse      = Sync_Pulse;          %
        
        
    end
    
    waitbar(trl/numel(ValidTrials));
    display(['Eye' CalOrEnd ' Trial ' Trl_TrialID(end-2:end) ' processing time : ' num2str(toc, '%3.3f') ' seconds']);
    % toc
end
close(hWaitBar);

MLStruct = HcTask_FormatEyeDataOffScreen(MLStruct, 0); % Modified by Ben Corrigan summer 2016

end
