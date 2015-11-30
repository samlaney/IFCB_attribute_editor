function attribute_editor
% gui to edit attribute file for a given IFCB8 file
% SRL Sept 2015
%   - heavily revised to take new approach to handling function calls
%
% will read or generate if new, the attributes file (*.atr) corresponding to the roi file
% action on 27 Sept 2015

clear all;  
close all force;



% establish the base handle for getappdata/setappdata
h_main = figure; 
set(h_main,'visible','off');    % make it initially invisible

setappdata(h_main,'selectallxfer',0); % a hack to help with the select all: shift-mouse won't work..


% these are for the autosave feature to save atr files every 5 min
% an atrfile autosave timer is started whenver an atr file is opened or created
% each file's timer is destroyed when file is closed/move on to next file
% timer default is single-shot. needs to be reset each time in callback

%remove all existing timers like this one
timers = timerfind('Name','atr_timer');
if ~isempty(timers),
    for i = 1:length(timers),
        fprintf('Deleting timer instance %d\n',i);
        stop(timers(i));
        delete(timers(i));
    end;
end;

setappdata(h_main,'atrfileautosaveperiod',2);     % minutes
setappdata(h_main,'atrfilesavetimer',timer('TimerFcn', {@atr_timer_update, h_main},... 
                 'StartDelay',getappdata(h_main,'atrfileautosaveperiod') * 60, ...
                 'Period',getappdata(h_main,'atrfileautosaveperiod') * 60, ...                 
                 'ExecutionMode','FixedRate',...
                 'Name','atr_timer') ); % needs to be in seconds
fprintf('Autosave timer init with period %d min\n',getappdata(h_main,'atrfileautosaveperiod'));

setappdata(h_main,'imageproctoolboxinstalled',license('test','image_toolbox') );
% this code needs grayslice (contained within) and imwrite to output TIFFs (not included)
if (getappdata(h_main,'imageproctoolboxinstalled') == 0),
    fprintf('No Image Processing Toolbox: some features disabled\n');
end;




%*********************************************************
%*** READ THE CONFIG FILE AND BRING IN RELEVANT CONFIG INFO
%*********************************************************

% this file contains all predefined key-value combinations
% read in each key names and then for each: names of possible values for each key
ret = load_config(h_main);
if (~ret),
    fprintf('Failure in load_config\n');
    h_errmsgbox = msgbox('Problem with load config','Config file error');
    beep;beep;
    pause(5);
    close(h_errmsgbox);
    fatalError('Config file failed\n', '', 'Config file failed', 5);
    return;
end;
clear ret;


% order of how keynames will appear in atr file and in tooltips, and default display
% displays will be 1 if not listed here
setappdata(h_main,'keyname_order', { ...
    'imgnum', false; 'lat', false; 'lon', false; 'station', false; 'cast', false; 'btl', false; ...
    'mlsampled', false; 'taxon', true; 'species', true; 'morpho', true  } ); 


% hopefully a 'taxon' field exists in appdata by the config file. 
% if not, create one and then stuff it with the default
% the rest are generated as needed from cfg file
if (~isappdata(h_main,'taxon')),
    setappdata(h_main,'taxon',[]);   % the bare minimum of default taxonomic classes
end;
setappdata(h_main,'taxon', [getappdata(h_main,'taxon'), {'unsorted_large' 'unsorted_small'}] );


% sort & reorder, to get alphabetically
setappdata(h_main,'taxon', unique(getappdata(h_main,'taxon')));

% settings for the options dialog box
setappdata(h_main,'options', {'Hide sorted', 0; 'Other options', 0} );


% SOME DEFINITIONS:
% the viewing frame is what you see in panel 1, size framex and fig_pos(4)
setappdata(h_main,'camx', 1380);    %camera image size - the maximum size of roi that will need to be displayed
setappdata(h_main,'camy', 1034);  
setappdata(h_main,'roismallsizethresh', 50);



% CREATE THE MAIN GUI WINDOW
createWindow(h_main);   
set(h_main,'visible','on');    % make it initially invisible


% now the window is set up and ready to receive instructions
fprintf('Program initialized\n');

end






%*******************************
% ERROR HANDLERS
%*******************************

function errorHandler(errstr, errdlgtitle)

    beep;beep;
    fprintf([errstr '\n']);
    uiwait(errordlg(errstr,errdlgtitle,'modal'));

end

function fatalError(msgboxstr, msgboxtitlestr, pauseval)

    fprintf(msgboxstr);
    errorHandler(msgboxstr,msgboxtitlestr);
    close all force;
    return;


end






%*******************************
% LOAD CONFIG FILE
%*******************************
% load the external config file with different keyname fields, etc
function retval = load_config(hndl)

retval = false; % default return value is false = failed / error


% see if there's an existing config file locally
if (length(dir(fullfile(pwd,'atr_config_default.txt'))) == 1 ),
    configfilename = 'atr_config_default.txt';
    configfilepath = pwd;
else
    [configfilename, configfilepath] = uigetfile('atr_config_*.txt','Select a config file');

    if isequal(configfilename,0) || isequal(configfilepath,0),
        fprintf('File selection input cancelled\n');
        h_errmsgbox = msgbox('No config file selected','File select error');
        beep;beep;
        pause(5);
        close(h_errmsgbox);
        return;
    end;
end;

fid = fopen(fullfile(configfilepath,configfilename));
if (fid == -1),
    fprintf('File selection input cancelled\n');
    h_errmsgbox = msgbox('Could not open config file','Config file error');
    beep;beep;
    pause(5);
    close(h_errmsgbox);
    return;
end;
  

% read in config file
C = textscan(fid, '%s', 'Delimiter',''); C = C{1};
fclose(fid);

% find start/end of each keyname
startIdx = find(ismember(C, '<KEYNAME>'));
endIdx = find(ismember(C, '</KEYNAME>'));

% do a quick check to see if they are the same length: must be
if (length(startIdx) ~= length(endIdx)),
    fatalError('Config file syntax: unequal brackets\n', 'Mismatched <KEYNAME>', 'Config syntax error', 5);
end;

keynames = struct('list',[]);
setappdata(hndl,'keynames',keynames);


for i = 1:numel(startIdx),  % loop through the various <KEYNAMES>
    % check to see that the next entry is after <KEYNAME> is valid name syntax
    knamestr = C{startIdx(i)+1};
    if (strcmp(knamestr(1:8),'keyname='))
        keynames = getappdata(hndl,'keynames');
        keynames.list = [keynames.list {knamestr(9:end)}];
        setappdata(hndl,'keynames',keynames);
        % create a <keyname> variable based on this entry
        setappdata(hndl,eval(' knamestr(9:end) '),[]);
    else
        break;
    end;

    % now fill in this <keyname> with all the valid (uncommented) keynames following
    for j = startIdx(i)+2:endIdx(i)-1,
        keyvalstr = C{j};
        if strcmp(keyvalstr(1),'#'),    
            % commented out; do not use this entry
        else    %otherwise add it to the string
            vals = [getappdata(hndl,eval(' knamestr(9:end) ')), {eval('keyvalstr')}];
            setappdata(hndl,eval([' knamestr(9:end) ']), vals );
        	%eval(['SETTINGS.' knamestr(9:end) ' = [SETTINGS.' knamestr(9:end) ' {keyvalstr}]; ']);
        end;
        
    end;

end;


% if program gets to here everything is good and can return true
retval = true;

end








%*******************************
% CREATE WINDOW
%*******************************


function createWindow(hndl)


% some screen parameters
%screen = get(0, 'ScreenSize');
%scr_wid = screen(3); scr_hig = screen(4);
% not sure why this doesn't work correctly
NET.addAssembly('System.Windows.Forms');
rect = System.Windows.Forms.Screen.PrimaryScreen.Bounds;
screensize = [rect.Width rect.Height];
scr_wid = rect.Width; scr_hig = rect.Height;
clear rect;
setappdata(hndl,'scr_width', scr_wid );
setappdata(hndl,'scr_height',scr_hig ); % throw a fit if the actual screen size isn't large enough for this


if (getappdata(hndl,'scr_width') < getappdata(hndl,'camx') || getappdata(hndl,'scr_height') < getappdata(hndl,'camy') ),
    % here return a message about screen resolution size
    errorHandler(sprintf('\nThis program should be run on a computer with a larger screen size, at least: %d x %d', ...
        getappdata(hndl,'camx'), getappdata(hndl,'camy')), 'Screen resolution issue');
  
else
    fprintf('\nScreen size seems OK\n');
end;



axis off;


% set window size to maximum initially
setappdata(hndl,'position', [getappdata(hndl,'scr_width')*0.01 getappdata(hndl,'scr_height')*0.05 ...
    getappdata(hndl,'scr_width')*0.75 getappdata(hndl,'scr_height')*.7] );


% set initial size of the window
set(hndl,'position',getappdata(hndl,'position') ); %pixels from LLHC, then width & height
colormap(gray);
set(hndl,'menubar', 'none');

build_menu(hndl);

set(hndl,'numbertitle','off');

set(hndl,'Units','pixels'); 
set(hndl,'color', 'w');
setappdata(hndl,'position', get(hndl,'Position') );
% callbacks
set(hndl,'keypressfcn',{@keypress_callback, hndl});
set(hndl,'ButtonDownFcn', {@mainframe_callback, hndl});
set(hndl,'ResizeFcn',{@guiresizereqestfcn, hndl});
set(hndl,'CloseRequestFcn',{@guiclosereqestfcn, hndl});

setappdata(hndl,'currpageindx', 1);  

% scrolling & frame viewing parameters
setappdata(hndl,'border', 10);         % matlab controls have a 5 pixel boundary

drawnow;

end




function build_menu(hndl)

setappdata(hndl,'mha',uimenu(gcf,'Label','File') );
setappdata(hndl,'eha1', uimenu(getappdata(hndl,'mha'),'Label','Open new ROI file','Callback',{@opendatafile, hndl}) );
setappdata(hndl,'eha2', uimenu(getappdata(hndl,'mha'),'Label','Update ATR file','Callback',{@write_atr_file, hndl}) );
setappdata(hndl,'eha3', uimenu(getappdata(hndl,'mha'),'Label','Close current ROI file','Callback',{@closedatafile, hndl}) );
setappdata(hndl,'eha4', uimenu(getappdata(hndl,'mha'),'Label','Exit','Callback',{@guiclosereqestfcn, hndl}) );

setappdata(hndl,'mhb', uimenu(gcf,'Label','View') );
setappdata(hndl,'ehb1', uimenu(getappdata(hndl,'mhb'),'Label','Refresh','Callback',@menu_refresh) );
setappdata(hndl,'ehb2', uimenu(getappdata(hndl,'mhb'),'Label','Options Dialog','Callback',{@options_dialog, hndl}) );

setappdata(hndl,'mhc', uimenu(gcf,'Label','*.atr Operations','Callback',{@menu_editatrfile, hndl}) );
set(getappdata(hndl,'mhc'),'Enable','off' );
%SETTINGS.ehc1 = uimenu(SETTINGS.mhc,'Label','Refresh','Callback',{@menu_refresh, hndl});

setappdata(hndl,'mhd', uimenu(gcf,'Label','Export images','Callback',{@menu_export_images, hndl}) );
%SETTINGS.ehd1 = uimenu(SETTINGS.mhc,'Label','Refresh','Callback',{@menu_refresh, hndl});
% menu_export_images depends on image toolbox imwrite for TIFF output
if (getappdata(hndl,'imageproctoolboxinstalled') == 0),
    set(getappdata(hndl,'mhd'),'Enable','off' );
end;

setappdata(hndl,'mhe',uimenu(gcf,'Label','Select All','Callback',{@image_select_all, hndl}) );

setappdata(hndl,'mhf', uimenu(gcf,'Label','Debug','Callback',{@menu_debug, hndl}) );


end



function menu_refresh(src,evnt)

generate_roitable(src);
updateroiframes(src);

end


function menu_editatrfile(src,evnt, hndl)

% save current file, open it for editing, then reload when done
fprintf('editing ATR file\n');
write_atr_file([],[],hndl);
edit(getappdata(hndl,'atrname'));

end

function menu_debug(src,evnt,hndl)
keyboard;
end










function opendatafile(src,evnt, hndl)


% ideally obviate this by disabling menu item
if (isappdata(hndl,'file'))
    % open file already
	errorHandler('Already an open file\n', 'File selection issue');
    return;
    
elseif (~isappdata(hndl,'filelist'))    % or no filelist selected yet
    
    [files, path] = uigetfile('*.roi','Multiselect','off');
    setappdata(hndl,'filelist',files);
    setappdata(hndl,'path',path);
    clear files path;

    % figure out if single or multiple file selected
    if ~iscell(getappdata(hndl,'filelist') ),
        setappdata(hndl,'filelist', { getappdata(hndl,'filelist') } );
    end;
    
    if isequal(getappdata(hndl,'filelist'),0) || isequal(getappdata(hndl,'path'),0),
        errorHandler('File selection input cancelled\n', 'File selection issue');
        return;
    end;
    setappdata(hndl,'filelist', sort(getappdata(hndl,'filelist') ));    % sort them in order
%    tmpval = getappdata(hndl,'filelist');
%    setappdata(hndl,'file', tmpval{1});
    setappdata(hndl,'fileindx', 1);    % index of active file in filelist
    
elseif ( isappdata(hndl,'filelist') && getappdata(hndl,'fileindx') < length(getappdata(hndl,'filelist')) )    % this is reached when prior multiselected files exist
    % there should be at least one more file in list: load that info and open it

%	tmpval = getappdata(hndl,'filelist');
%    setappdata(hndl,'file', tmpval{ getappdata(hndl,'fileindx') + 1 });
    setappdata(hndl,'fileindx', getappdata(hndl,'fileindx')+1);    % index of active file in filelist

elseif ( getappdata(hndl,'fileindx') == length(getappdata(hndl,'filelist')) )    % this is reached when prior multiselected files exist
	errorHandler('No additional files in file list or other issue\n', 'File selection issue');
    return;
   
   
else
    % either no more files to load in filelist
	errorHandler('File selection input problem\n', 'File selection issue');
    return;
end;


% check for valid path/file name and continue
if isequal(getappdata(hndl,'filelist'),0) || isequal(getappdata(hndl,'path'),0),
    errorHandler('Bad choice of file or path\n','File choice error');
    return;
else
    load_currentsession(getappdata(hndl,'fileindx'),hndl);    % launch the editing window with file-specific data
end;



% a file is open: disable and grey out the file input menu selection
%set(getappdata(hndl,'eha1'),'Enable','off' );




end





function closedatafile(src,evnt, hndl)


% is there an open file?
if (isappdata(hndl,'file')),
    
    
    fprintf('Closing IFCB atr file for %s\n',fullfile(getappdata(hndl,'path'), getappdata(hndl,'file')) );    
    
    % prompt for saving attribute file
    ButtonName = questdlg('Save the *.atr file?', ...
        'Save Attributes to file', ...
        'Yes', 'No', 'Yes');
    switch ButtonName,
        case 'Yes',
            write_atr_file([],[],hndl);
    end % switch
    
    rmappdata(hndl,'file');    % now there is no active file
    
    
    % are there more files in this filelist?
    % be smart to make this not recursive
    if (getappdata(hndl,'fileindx') < length(getappdata(hndl,'filelist')) )
        
        % prompt for opening next file
        ButtonName = questdlg('Edit next file?', ...
            'Next file?', ...
            'Yes', 'No', 'No');
        switch ButtonName,
            case 'Yes',
% think about this calling convention
                load_currentsession('nextfile', hndl);
                return;
        end % switch
    
    else    % there are no more files in filelist
        clear_currentsession(hndl);
        rmappdata(hndl,'filelist');    % now there is no active filelist
        % some way to zero out all the images in the screen?
    
    end;
    
    
end;


end











%*******************************
% LOAD CURRENT SESSION
%*******************************

function load_currentsession(indx, hndl)
% indx here is the pointer of which file in filelist
% if zero, a null file (create an empty window)

% zero out all appdata before loading this file
clear_currentsession(hndl);


% set a message to ask user to be patient
set(hndl,'name','Please wait - datafile loading');
set(hndl,'Pointer','watch');    % set mouse to hourglass
drawnow;


if (indx == 0),
    errorHandler('zero index\n' , 'error in load_currentsession');
    return;
end;


% start loading up file indicated by fileindx
tmpval = getappdata(hndl,'filelist');
setappdata(hndl,'fileindx', 1);    % index of active file in filelist
setappdata(hndl,'file', tmpval{1});
clear tmpval;


% retrieve the relevant data from ROI, ADC, HDR, & ATR files
importIFCBdata(hndl);

generate_roitable(hndl);  % given the filtering, determine which rois are to be displayed (e.g. all?)

updateroiframes(hndl);

set(hndl,'Pointer','arrow');    % set mouse to back to pointer
drawnow;


% a temporary hack for the dialog box "display only" sense of the display fields in morpho and species
%eval('for i = 1:length(SETTINGS.attrib.species.name), SETTINGS.attrib.species.display(i) = false; end; ');
%eval('for i = 1:length(SETTINGS.attrib.morpho.name), SETTINGS.attrib.morpho.display(i) = false; end; ');
attrib = getappdata(hndl,'attrib');
eval('for i = 1:length(attrib.species.name), attrib.species.display(i) = false; end; ');
eval('for i = 1:length(attrib.morpho.name), attrib.morpho.display(i) = false; end; ');
setappdata(hndl,'attrib',attrib);


% if there isn't a modal options dialog already open, open one
if ~isappdata(hndl,'h_optsdlg'), 
    options_dialog([],[],hndl);
end;



% start the autosave timer for the atr file
start(getappdata(hndl,'atrfilesavetimer'));


end



% reset/erase current session data
function clear_currentsession(hndl)

    setappdata(hndl,'h_im',[]); % these need to be defined before use
    setappdata(hndl,'h_txt',[]);
    setappdata(hndl,'selectedimages',[]);
    setappdata(hndl,'page',[]);
    setappdata(hndl,'tiff_outdir',[]);
    setappdata(hndl,'images_to_display',0);

    setappdata(hndl,'adcdata',[]);
    setappdata(hndl,'num_imgs',[]);
    setappdata(hndl,'imgnum',[]);
    setappdata(hndl,'trigger',[]);
    setappdata(hndl,'xsize',[]);
    setappdata(hndl,'ysize',[]);
    setappdata(hndl,'startbyte',[]);
    setappdata(hndl,'xdata',[]);
    setappdata(hndl,'ydata',[]);
    setappdata(hndl,'attrib',[]);
    setappdata(hndl,'attributes',[]);

   
	stop(getappdata(hndl,'atrfilesavetimer'));
    
    
end






function options_dialog(src,evnt,hndl)

% to display which types of rois, control program function, etc.
% whether the image values are scaled or raw for display
% which of the various key-value pairs to display (checkboxes)

% create the dialog
% if there's a options dialog open, skip this

if (~isappdata(hndl,'h_optsdlg') || isempty(getappdata(hndl,'h_optsdlg')) ), 
    setappdata(hndl,'h_optsdlg', dialog('Name','Options Dialog','WindowStyle','normal') );
    set(getappdata(hndl,'h_optsdlg'),'Units','normalized','Position', [0.65 0.1 0.3 0.8 ] );
    set(getappdata(hndl,'h_optsdlg'),'CloseRequestFcn',{@option_dlg_close, hndl});
    set(getappdata(hndl,'h_optsdlg'),'keypressfcn',{@keypress_callback, hndl});
else
    fprintf('Options dialog already open\n');
    return;
end;



% top left
% for general options dialog items
xllc = 0; yllc = 0.9; xwidth = 0.3; yheight = 0.1;
h_opts1 = uibuttongroup('parent',getappdata(hndl,'h_optsdlg'),'visible','off','Position',[xllc, yllc, xwidth, yheight]);
% get the box size in cm
set(h_opts1,'units','centimeters'); cm_dims = get(h_opts1,'position');
options = getappdata(hndl,'options');
for i =1:length(options),
    % remember: the logical units here are relative to the box height
    u_opts1(i) = uicontrol('Style','Checkbox','Callback',{@service_options, options{i,1},hndl }, ...
        'String', options{i,1},'units','centimeters','pos',[0.1 (cm_dims(4)-0.5-i*0.5) cm_dims(3)-0.1 0.5], ...
        'parent',h_opts1,'HandleVisibility','off');
    if options{i,2} == 1
        set(u_opts1(i),'value',1);
    else
        set(u_opts1(i),'value',0);
    end;
end;
set(h_opts1,'units','normalized');
set(h_opts1,'SelectedObject',[]);  % No selection
set(h_opts1,'Visible','on');
%[10  (400-i*20) 100 20]



% middle left
% button group for keynames to display
xllc = 0; yllc = 0.6; xwidth = 0.3; yheight = 0.3;
h_opts2 = uibuttongroup('parent',getappdata(hndl,'h_optsdlg'),'visible','off','Position',[xllc, yllc, xwidth, yheight]);
% get the box size in cm
set(h_opts2,'units','centimeters'); cm_dims = get(h_opts2,'position');
attrib = getappdata(hndl,'attrib');
for i =1:length(attrib.keynames),
    u_opts2(i) = uicontrol('Style','Checkbox','Callback',@service_keyname_checkboxes,'String', ...
        attrib.keynames{i},'units','centimeters','pos',[0.1 (cm_dims(4)-0.5-i*0.5) cm_dims(3)-0.1 0.5], ...
        'parent',h_opts2,'HandleVisibility','off');
end;
set(h_opts2,'units','normalized');
set(h_opts2,'SelectedObject',[]);  % No selection
set(h_opts2,'Visible','on');
for j = 1:length(attrib.keynames),
    if (attrib.keynames{j,2}),     % if this taxon is selected for display, check the box
        set(u_opts2(j),'value',1);
    else
        set(u_opts2(j),'value',0);
    end;
end;



% 3rd down left
% checkboxes to include subsets of 'morpho' when choosing what to display
xllc = 0; yllc = 0.3; xwidth = 0.3; yheight = 0.3;
h_opts4 = uibuttongroup('parent',getappdata(hndl,'h_optsdlg'),'visible','off','Position',[xllc, yllc, xwidth, yheight]);
% get the box size in cm
set(h_opts4,'units','centimeters'); cm_dims = get(h_opts4,'position');
for i =1:length(attrib.morpho.name),
    u_opts4(i) = uicontrol('Style','Checkbox','Callback',@service_morpho_checkboxes,'String', ...
        [attrib.morpho.name{i} ],'units','centimeters','pos',[0.1 (cm_dims(4)-1-i*0.5) cm_dims(3)-0.1 0.5], ...
        'parent',h_opts4,'HandleVisibility','off');
end;
u_opts4(i+1) = uicontrol('Style','text','String', 'Show only','units','centimeters','Position',[0.1 cm_dims(4)-0.9 2 0.5],'parent',h_opts4);
%u_opts4(i+2) = uicontrol('Style','Pushbutton','Callback',{@service_morpho_setalldisplay, 'on'},'String', 'Display all' , 'pos',[10  395  70 20],'parent',h_opts4,'HandleVisibility','off');
%u_opts4(i+3) = uicontrol('Style','Pushbutton','Callback',{@service_morpho_setalldisplay, 'off'},'String', 'Clear all' , 'pos',[10  375  70 20],'parent',h_opts4,'HandleVisibility','off');
set(h_opts4,'units','normalized');
set(h_opts4,'SelectedObject',[]);  % No selection
set(h_opts4,'Visible','on');

for j = 1:length(attrib.morpho.name),
    if (attrib.morpho.display(j) == true),     % if this taxon is selected for display, check the box
        set(u_opts4(j),'value',1);
    else
        set(u_opts4(j),'value',0);
    end;
end;




%bottom left
% checkboxes to include subsets of 'species' when choosing what to display
xllc = 0; yllc = 0; xwidth = 0.3; yheight = 0.3;
h_opts5 = uibuttongroup('parent',getappdata(hndl,'h_optsdlg'),'visible','off','Position',[xllc, yllc, xwidth, yheight]);
% get the box size in cm
set(h_opts5,'units','centimeters'); cm_dims = get(h_opts5,'position');
for i =1:length(attrib.species.name),
    u_opts5(i) = uicontrol('Style','Checkbox','Callback',@service_species_checkboxes,'String', ...
        [attrib.species.name{i} ],'units','centimeters','pos',[0.1 (cm_dims(4)-1-i*0.5) cm_dims(3)-0.1 0.5], ...
        'parent',h_opts5,'HandleVisibility','off');
end;
u_opts5(i+1) = uicontrol('Style','text','String', 'Show only','units','centimeters','Position',[0.1 cm_dims(4)-0.9 2 0.5],'parent',h_opts5);
%u_opts5(i+2) = uicontrol('Style','Pushbutton','Callback',{@service_morpho_setalldisplay, 'on'},'String', 'Display all' , 'pos',[10  395  70 20],'parent',h_opts5,'HandleVisibility','off');
%u_opts5(i+3) = uicontrol('Style','Pushbutton','Callback',{@service_morpho_setalldisplay, 'off'},'String', 'Clear all' , 'pos',[10  375  70 20],'parent',h_opts5,'HandleVisibility','off');
set(h_opts5,'units','normalized');
set(h_opts5,'SelectedObject',[]);  % No selection
set(h_opts5,'Visible','on');

for j = 1:length(attrib.species.name),
    if (attrib.species.display(j) == true),     % if this taxon is selected for display, check the box
        set(u_opts5(j),'value',1);
    else
        set(u_opts5(j),'value',0);
    end;
end;








% middle column
% button group for taxon selected to display
xllc = 0.3; yllc = 0; xwidth = 0.7; yheight = 1;
h_opts3 = uibuttongroup('parent',getappdata(hndl,'h_optsdlg'),'visible','off','Position',[xllc, yllc, xwidth, yheight]);
% get the box size in cm
set(h_opts3,'units','centimeters'); cm_dims = get(h_opts3,'position');
found_colend = 0;   % flags when column end is found
for i =1:length(attrib.taxon.name),
    % see if it will be placed on first row or second
    pos = [0.1 (cm_dims(4)-1-i*0.5) 4 0.5];  %cm_dims(3)-0.1
    if (pos(2) <= 0.1),
        if found_colend == 0,
            found_colend = 1;
            col_end = i;
        end;
        pos = [4.1 (cm_dims(4)-1.5-(i-col_end)*0.5) 4 0.5];
    end;
    
    u_opts3(i) = uicontrol('Style','Checkbox','Callback',@service_taxon_checkboxes,'String', ...
        attrib.taxon.name{i},'units','centimeters','pos',pos, ...
        'parent',h_opts3,'HandleVisibility','off');
end;

u_opts3(i+1) = uicontrol('Style','text','String', 'taxon','units','centimeters','Position',[0.1 cm_dims(4)-0.9 1 0.5],'parent',h_opts3);
u_opts3(i+2) = uicontrol('Style','Pushbutton','Callback',{@service_taxon_setalldisplay, hndl, 'on'},'String', 'Display all' , ...
    'units','centimeters', 'pos',[1.25 cm_dims(4)-1 2 0.75],'parent',h_opts3,'HandleVisibility','off');
u_opts3(i+3) = uicontrol('Style','Pushbutton','Callback',{@service_taxon_setalldisplay, hndl, 'off'},'String', 'Clear all' , ...
    'units','centimeters', 'pos',[3.5 cm_dims(4)-1 2 0.75],'parent',h_opts3,'HandleVisibility','off');
set(h_opts3,'units','normalized');
set(h_opts3,'SelectedObject',[]);  % No selection
set(h_opts3,'Visible','on');

for j = 1:length(attrib.taxon.name),
    if (attrib.taxon.display(j) == true),     % if this taxon is selected for display, check the box
        set(u_opts3(j),'value',1);
    else
        set(u_opts3(j),'value',0);
    end;
end;






    % NOTE!!!
    % when nesting in Matlab the scope of variables is not what you might think!!
    % hence the messy business with underscored variables in each nested fn


    function service_species_checkboxes(src,evnt, hndl_a)
        % change the status of the requested taxon.display
         keyname = get(src,'String');
        attrib_a = getappdata(hndl_a,'attrib');
         for k=1:length(attrib_a.species.name),
            if strcmp(attrib_a.species.name{k}, keyname),
                attrib_a.species.display(k) = ~attrib_a.species.display(k);
            end;
         end;
         setappdata(hndl_a,'attrib',attrib_a);
         
        % if any selected values have changed, regenerate the roitable with the right subset of images
        find_displayable_images('taxon', hndl_a);
        generate_roitable(hndl_a);
        setappdata(hndl_a,'currpageindx', 1);
    
    end


%     function service_species_setalldisplay
%     end



    function service_morpho_checkboxes(src,evnt, hndl_b)
        % change the status of the requested taxon.display
         keyname = get(src,'String');
        attrib_b = getappdata(hndl_b,'attrib');
         for k=1:length(attrib_b.morpho.name),
            if strcmp(attrib_b.morpho.name{k}, keyname),
                attrib_b.morpho.display(k) = ~attrib_b.morpho.display(k);
            end;
         end;
        setappdata(hndl_b,'attrib',attrib_b);
        
        % if any selected values have changed, regenerate the roitable with the right subset of images
        find_displayable_images('taxon', hndl_b);
        generate_roitable(hndl_b);
        setappdata(hndl_b,'currpageindx', 1);
    
    end
%     function service_morpho_setalldisplay
%     end




    % function to service the calls for keyname checkbox
    function service_keyname_checkboxes(src,evnt, hndl_c)
        % change the status of the requested keyname displays in the tooltips
         keyname = get(src,'String');
         attrib_c = getappdata(hndl_c,'attrib');
         for k=1:length(attrib_c.keynames),
            if strcmp(attrib_c.keynames{k}, keyname),
                attrib_c.keynames{k,2} = ~attrib_c.keynames{k,2};
            end;
         end;
        setappdata(hndl_c,'attrib',attrib_c);
         
        % if any selected values have changed, regenerate the roitable with the right subset of images
        find_displayable_images('taxon', hndl_c);
        generate_roitable(hndl_c);
        setappdata(hndl_c,'currpageindx', 1);
    
    end


% function to set all taxon fields to visible or not
    function service_taxon_setalldisplay(src,evnt,hndl_d,arg1)
        attrib_d = getappdata(hndl_d,'attrib');
        for k=1:length(attrib_d.taxon.name),
            if strcmp(arg1,'on'),
                attrib_d.taxon.display(k) = true;
                % refresh the checkboxes in the taxon table
                set(u_opts3(k),'value',1);
            elseif strcmp(arg1,'off')
                attrib_d.taxon.display(k) = false;
                % refresh the checkboxes in the taxon table
                set(u_opts3(k),'value',0);
            else
                uiwait(msgbox('error in service_taxon_setalldisplay'));
            end;
        end;
        setappdata(hndl_d,'attrib',attrib_d);
        
        setappdata(hndl_d,'images_to_display', 1:getappdata(hndl_d,'num_imgs') ); % all of them
        generate_roitable(hndl_d);
%        menu_refresh();                         % refresh frame just in case

    end


    % function to service the calls for each checkbox
    function service_taxon_checkboxes(src,evnt, hndl_e)
        % change the status of the requested taxon.display
         keyname = get(src,'String');
         attrib_e = getappdata(hndl_e,'attrib');
         for k=1:length(attrib_e.taxon.name),
            if strcmp(attrib_e.taxon.name{k}, keyname),
                attrib_e.taxon.display(k) = ~attrib_e.taxon.display(k);
            end;
         end;
        setappdata(hndl_e,'attrib',attrib_e);
         
        % if any selected values have changed, regenerate the roitable with the right subset of images
        find_displayable_images('taxon', hndl_e);
%        generate_roitable(hndl);
        menu_refresh();                         % refresh frame just in case
        setappdata(hndl_e,'currpageindx', 1);
    
    end



    % function to execute when dialog is closed
    function option_dlg_close(src,evnt, hndl_f)
        %resort what to display
    %        SETTINGS = generate_roitable(SETTINGS)(roi_indices)        
        % reissue a repaint of the frames
        updateroiframes(hndl_f);

        closereq;

        setappdata(hndl_f,'h_optsdlg', []);    % null the field before removing it

    end


    % function to service the general options
    function service_options(src,evnt,optparam, hndl_g)
        val = get_option_status(optparam, hndl_g);      % get the current value of this options parameter
        set_option_status(optparam, ~val, hndl_g);      % and invert it
        menu_refresh(hndl_g);                         % refresh frame just in case
    end



end










function retval = get_option_status(optionparam, hndl)

retval = [];
options = getappdata(hndl,'options');
for i = 1:length(options),
    if strcmp(options{i,1},optionparam)
        retval = options{i,2};
        break;
    end;
end;

end

function set_option_status(optionparam, val, hndl)

options = getappdata(hndl,'options');
for i = 1:length(options),
    if strcmp(options{i,1},optionparam)
        	options{i,2} = val;
        break;
    end;
end;
setappdata(hndl,'options',options);

end




function find_displayable_images(keyname, hndl)

% input is the keyname to check on displayability, e.g., 'taxon'
% output of this function is the properly filled SETTINGS.images_to_display array
set(hndl,'images_to_display', []);

if strcmp(keyname,'taxon'),
    displayable = [];
    attrib = getappdata(hndl,'attrib');
    for i=1:length(attrib.taxon.name)
        if (attrib.taxon.display(i) )
            displayable = [displayable attrib.taxon.name(i)];
        end;
    end;

    images_to_display = getappdata(hndl,'images_to_display');
    imgnum = getappdata(hndl,'imgnum');
    for i=1:getappdata(hndl,'num_imgs'),
        % is there a proper keyname field and is it displayable
        val1 = get_attrib(i, 'taxon', hndl);

        if ( ismember(val1,displayable) ),    % if it's a displayable taxon

            % are morpho categories all unselected? if not, need to exclude some
            if (~isempty(find(attrib.morpho.display,1))),    % at least one morpho box is ticked
                % find out which ones are ticked
                % only include those
                val2 = get_attrib(i, 'morpho', hndl);                
                for j = 1:length(attrib.morpho.name),
                    if (strcmp(val2,attrib.morpho.name{j})),
                        images_to_display = [images_to_display imgnum(i)];
                    end;
                end;
            elseif (~isempty(find(attrib.species.display,1)))
                % find out which ones are ticked
                % only include those
                val2 = get_attrib(i, 'species', hndl);                
                for j = 1:length(attrib.species.name),
                    if (strcmp(val2,attrib.species.name{j})),
                        images_to_display = [images_to_display imgnum(i)];
                    end;
                end;
            else                
                images_to_display = [images_to_display imgnum(i)];
            end;

        end;
    end;
    setappdata(hndl,'images_to_display', images_to_display);
    
end;



end





%***********************************
% ATTRIBUTE MANIPULATION FUNCTIONS
%***********************************


function value = get_attrib(imgnum, keyname, hndl)
% give it an index in the master array of images, and a keyname, 
% it returns the value associated in SETTINGS.attrib(indx)
% or empty array otherwise

value = [];

attributes = getappdata(hndl,'attributes');
tmp = attributes{imgnum};
for j = 1:length(tmp),  % go through the various key-value pairs in this entry: not all the same length
    indx = strfind(tmp{j}, [keyname '='] );
    if ~isempty( indx ),    % this one has a matching key entry in it
        value = tmp{j}(length(keyname)+2:end);
    end;
end;

end



function set_attrib(imgnum, keyname, val, hndl)
% sets the attribute of image imgnum, associated with keyname, to val
% need to make it smart in case there isn't an entry already in it's attribute field

attributes = getappdata(hndl,'attributes');
tmp = attributes{imgnum};
for j = 1:length(tmp),  % go through the various key-value pairs in this entry: not all the same length

    indx = strfind(tmp{j}, [keyname '='] );
    if ~isempty( indx ),    % this one has a matching key entry in it
        break;  % get out of the loop at this j
    end;
    
end;

if isempty( indx )
    j = j + 1;
end;

tmp{j} = strcat(keyname,'=',val);
attributes{imgnum} = tmp;

setappdata(hndl,'attributes',attributes);

end


function del_attrib(imgnum, keyname, hndl)

attributes = getappdata(hndl,'attributes');
[m, n] = size(attributes{imgnum});
if (m-1 < 0),  % trying to delete somthing from an empty attributes
    return; 
end;

tmp = cell(m-1,n);  % sized one row shorter
incr = 1;
for j = 1:length( attributes{imgnum} ),  % go through the various key-value pairs in this entry: not all the same length
    indx = strfind(attributes{imgnum}{j}, [keyname '='] );
    if isempty( indx ),    % this one has a matching key entry in it
        tmp{incr} = attributes{imgnum}{j};
        incr = incr + 1;
    end;
end;
attributes{imgnum} = tmp;

setappdata(hndl,'attributes',attributes);
end

function sort_attrib(imgnum, hndl)
% this function will sort key-value pairs in an attribute entry into an order
% specified by a predetermined list of keynames (e.g., imgnum, lat, lon, etc)
% established in SETTINGS.attrib.keynames during SETTINGS = read_atr_file(SETTINGS)


attributes = getappdata(hndl,'attributes');
tmp = attributes{imgnum};

%keyboard



end






%***********************************
% ATTRIBUTE DIALOG MENU
%***********************************


function ok = attribute_dialog(h_image, keyname, hndl)
% function to generate a recursive selection box to allow user to select attributes
% that can in turn be left-clicked to select, or right-clicked to go deeper into remaining attributes

% for now, we start with 'taxon' and then choose from remaining 'species' and 'morpho'
%
% when a choice is selected, it is written to SETTINGS and dialog closes
%
% the function receives the handle to the image it was right-clicked on
% and the attribute keyname being selected (e.g., 'taxon' as a string)
%
% it also may be that many other images are selected too, so operate on those as well
% function also returns an OK to allow calling function to know when is done

ok = 1;

% get the roi index of the most recently right-clicked image
final_image_num = get(h_image,'UserData');
% and add it to the list of already selected
setappdata(hndl,'selectedimages', unique([getappdata(hndl,'selectedimages') final_image_num ]) ); % in case it's already selected

% now find out what to do with these selected images
% display the choices for this attribute keyname, in a dialog that has as callback a
% function that can tell if left-clicked or right-clicked
waitfor(display_keyname_dlg(keyname, hndl));

setappdata(hndl,'selectedimages', [] );   % zero out selected images list
generate_roitable(hndl);
updateroiframes(hndl);                % redraw the window
drawnow;



    function h_attribdlg = display_keyname_dlg(keyname, hndl_a)
        % generate a dialog menu with the appropriate list of keyname choices
        % making it modal will ensure that it will stay on top until a selection is made
        % keyname is a string
        h_attribdlg = dialog('Name','Attributes Dialog','WindowStyle','normal'); %'modal');  % 'normal'
        set(h_attribdlg,'Units','normalized','Position', [0.65 0.1 0.3 0.8 ] );
        set(h_attribdlg,'CloseRequestFcn',@attrib_dlg_close);


        attrib = getappdata(hndl_a,'attrib');
        liststr = [];
        keyname = 'taxon';
        %********** first button group
        h_attrib1 = uibuttongroup('parent',h_attribdlg,'visible','off','Position',[0 0 0.7 1]);
        len = 0;    % need this to fake out the scoping of eval, when nested or anonymous functions
        eval([ 'len = length(attrib.' keyname '.name); ' ]);
        % get the box size in cm
        set(h_attrib1,'units','centimeters'); cm_dims = get(h_attrib1,'position');

        % generate the various buttons that go in this window
        found_colend = 0;
        for i =1:len,
            % see if it will be placed on first row or second
            pos = [0.2 (cm_dims(4)-1-i*0.5) 3 0.5];  %cm_dims(3)-0.1
            if (pos(2) <= 0.1),
                if found_colend == 0,
                    found_colend = 1;
                    col_end = i;
                end;
                pos = [4.1 (cm_dims(4)-1.5-(i-col_end)*0.5) 3 0.5];
            end;        
            
            u_attrib1(i) = uicontrol('Style','pushbutton', 'units','centimeters','pos', pos, ... 
                'enable','inactive','parent',h_attrib1,'HandleVisibility','off');
            % give it the appropriate callback for this keyname
            eval([ 'set(u_attrib1(i), ''buttondownfcn'',{@attrib_select, ''' keyname ''', attrib.' keyname '.name{i} , hndl_a} ); ']);
            % and set the string to what it should be, for this keyname
            eval([ 'set(u_attrib1(i), ''String'', attrib.' keyname '.name{i} ); ']);
        end;
        i = i+1;
%         u_attrib1(i) = uicontrol('Style','pushbutton','buttondownfcn',{@attrib_select, keyname, 'Add a new choice' }, ...    % empty string being returned
%             'String', 'Add a new choice' , 'units', 'centimeters', 'pos',[0.2 cm_dims(4)-0.5 3 0.5], ...
%             'enable','inactive','parent',h_attrib1,'HandleVisibility','off');
%         i = i+1;
%         u_attrib1(i) = uicontrol('Style','pushbutton','buttondownfcn',{@attrib_select, keyname, 'Delete attribute' }, ...    % empty string being returned
%             'String', 'Delete attribute' ,'units', 'centimeters', 'pos',[3.2 cm_dims(4)-0.5 3 0.5], ...
%             'enable','inactive','parent',h_attrib1,'HandleVisibility','off');

        eval([ 'liststr = [attrib.' keyname '.name {''Add new choice'' ''Delete attribute''}]; ']);
        set(h_attrib1,'SelectedObject',[]);  % No selection
        set(h_attrib1,'Visible','on');

       

        keyname = 'species';        
        %********** second button group
        h_attrib2 = uibuttongroup('parent',h_attribdlg,'visible','off','Position',[0.7 0 0.3 0.5]);
        len = 0;    % need this to fake out the scoping of eval, when nested or anonymous functions
        eval([ 'len = length(attrib.' keyname '.name); ' ]);
        % get the box size in cm
        set(h_attrib2,'units','centimeters'); cm_dims = get(h_attrib2,'position');
        % generate the various buttons that go in this window
        for i =1:len,
            u_attrib2(i) = uicontrol('Style','pushbutton', 'units','centimeters','pos',[0.2 (cm_dims(4)-1-i*0.5) cm_dims(3)-0.4 0.5], ... 
                'enable','inactive','parent',h_attrib2,'HandleVisibility','off');
            % give it the appropriate callback for this keyname
            eval([ 'set(u_attrib2(i), ''buttondownfcn'',{@attrib_select, ''' keyname ''', attrib.' keyname '.name{i}, hndl_a } ); ']);
            % and set the string to what it should be, for this keyname
            eval([ 'set(u_attrib2(i), ''String'', attrib.' keyname '.name{i} ); ']);
        end;

%         i = i+1;
%         u_attrib2(i) = uicontrol('Style','pushbutton','buttondownfcn',{@attrib_select, keyname, 'Add a new choice' }, ...    % empty string being returned
%             'String', 'Add a new choice' ,'units','centimeters', 'pos',[0.1 cm_dims(4)-3 2 0.5], ...
%             'enable','inactive','parent',h_attrib2,'HandleVisibility','off');
%         i = i+1;
%         u_attrib2(i) = uicontrol('Style','pushbutton','buttondownfcn',{@attrib_select, keyname, 'Delete attribute' }, ...    % empty string being returned
%             'String', 'Delete attribute' ,'units','centimeters', 'pos',[0.1 cm_dims(4)-3.5 2 0.5], ...
%             'enable','inactive','parent',h_attrib2,'HandleVisibility','off');

        eval([ 'liststr = [attrib.' keyname '.name {''Add new choice'' ''Delete attribute''}]; ']);
        set(h_attrib2,'units','normalized');
        set(h_attrib2,'SelectedObject',[]);  % No selection
        set(h_attrib2,'Visible','on');
        
        
        

        keyname = 'morpho';        
        %********** third button group
        h_attrib3 = uibuttongroup('parent',h_attribdlg,'visible','off','Position',[0.7 0.5 0.3 0.5]);
        len = 0;    % need this to fake out the scoping of eval, when nested or anonymous functions
        eval([ 'len = length(attrib.' keyname '.name); ' ]);
        % get the box size in cm
        set(h_attrib3,'units','centimeters'); cm_dims = get(h_attrib3,'position');

        % generate the various buttons that go in this window
        for i =1:len,
            u_attrib3(i) = uicontrol('Style','pushbutton','units','centimeters','pos',[0.2 (cm_dims(4)-1-i*0.5) cm_dims(3)-0.4 0.5], ... 
                'enable','inactive','parent',h_attrib3,'HandleVisibility','off');
            % give it the appropriate callback for this keyname
            eval([ 'set(u_attrib3(i), ''buttondownfcn'',{@attrib_select, ''' keyname ''', attrib.' keyname '.name{i}, hndl_a } ); ']);
            % and set the string to what it should be, for this keyname
            eval([ 'set(u_attrib3(i), ''String'', attrib.' keyname '.name{i} ); ']);
        end;
%         i = i+1;
%         u_attrib3(i) = uicontrol('Style','pushbutton','buttondownfcn',{@attrib_select, keyname, 'Add a new choice' }, ...    % empty string being returned
%             'String', 'Add a new choice' ,'units','centimeters', 'pos',[0.1 cm_dims(4)-3 2 0.5], ...
%             'enable','inactive','parent',h_attrib3,'HandleVisibility','off');
%         i = i+1;
%         u_attrib3(i) = uicontrol('Style','pushbutton','buttondownfcn',{@attrib_select, keyname, 'Delete attribute' }, ...    % empty string being returned
%             'String', 'Delete attribute' , 'units','centimeters', 'pos',[0.1 cm_dims(4)-3.5 2 0.5], ...
%             'enable','inactive','parent',h_attrib3,'HandleVisibility','off');

        eval([ 'liststr = [attrib.' keyname '.name {''Add new choice'' ''Delete attribute''}]; ']);
        set(h_attrib2,'units','normalized');
        set(h_attrib3,'SelectedObject',[]);  % No selection
        set(h_attrib3,'Visible','on');
        
        
    end





    function attrib_select(src, evnt, key_name, key_val, hndl_b)
        % what gets called when an attribute is selected, right or left click
        % input is src & evnt, arg1 is the name of the taxon selected (the button), keyname is the type of attribute being selected
        seltype = get(gcf,'selectiontype'); % need to go all the way to the main figure for this
    
        attrib = getappdata(hndl_b,'attrib');
        selectedimages = getappdata(hndl_b,'selectedimages');
        
        if strcmp(seltype,'normal'),
            % just process the selection and return
            % maybe be smarter with inarg

            if (strcmp(key_val, 'Delete attribute')), % delete this entry from the SETTINGS.attributes for this image

                for i = 1:length(selectedimages),
                    im_num = selectedimages(i);
                    % force the replacement
                    del_attrib(im_num, key_name, hndl_b);  %delete current attribute entry
                end;
                return;
                
            elseif (strcmp(key_val, 'Add a new choice')), % if asking to add a new category
                % prompt an input dialog box
                answer=inputdlg('Enter name of new category','Add new value',1,{''});
                if (~strcmp(answer,''))

                    % add to SETTINGS.attrib.<key_name>.name
                    eval ([ 'attrib.' key_name '.name = [attrib.' key_name '.name answer]; ']);
                    % append a matching entry in display field
                    eval ([ 'attrib.' key_name '.display = [attrib.' key_name '.display true]; ']);
                    % and sort each accordingly
                    i_indx = []; j_indx = [];
                    eval ([ '[attrib.' key_name '.name, i_indx, j_indx] = unique(attrib.' key_name '.name); ']);
                    eval ([ 'attrib.' key_name '.display = attrib.' key_name '.display(i_indx); ']);

                    % find the index of this new entry within attrib
                    c = []; sel = []; ab = [];
                    eval ([ '[c, sel, ab] = intersect(attrib.' key_name '.name, answer); ']);
                    key_val = answer;
                end;
            end;
            setappdata(hndl_b,'attrib',attrib);
            
            % now edit the SETTINGS.attrib to all selected images
            for i = 1:length(selectedimages),

                im_num = selectedimages(i);
                % force the replacement
                set_attrib(im_num, key_name, key_val, hndl_b);  %set this into current attribute
                sort_attrib( im_num , hndl_b);

            end;
            

        elseif strcmp(seltype,'alt')
            % a right-click launches this again, with the remaining subset of keynames in two other columns
            % determine which are the remaining key_names to consider

%             waitfor(display_keyname_dlg(next_key_name, hanndd));
            
        else % shouldn't be here
            beep;
            errordlg(['Function is receiving ' seltype], 'Error in attrib_select', 'modal');

        end;

        % if clicking on on the first column, close this dialog.
        keynames = getappdata(hndl_b,'keynames');
        if (strcmp(key_name,keynames.list{1} )),
            attrib_dlg_close([],[]);            
        end;

    end



    function attrib_dlg_close(src,evnt)
        % function to execute when attrib dialog is closed
         closereq;
    end

end








%***********************************
% GUI FUNCTIONS
%***********************************


%***********************************
% guiresizerequestfcn
%***********************************
function guiresizereqestfcn(src,evnt, hndl)

    % get the new figure position information from the handle
    setappdata(hndl,'position', get(getappdata(hndl,'h_main'),'Position') );
    

    generate_roitable(hndl);
    updateroiframes(hndl);                % redraw the window
    drawnow;
    beep;

end



%***********************************
% gucloserequestfcn
%***********************************

function guiclosereqestfcn(src,evnt, hndl)
% things to do when shutting down

% delete the timer
delete(getappdata(hndl,'atrfilesavetimer'));

fclose all;   % close any open files

% if there is an open file, close it & timers
closedatafile(src,evnt, hndl);


% eliminate all app data
appdatanames = fieldnames(getappdata(hndl));
for i = 1:length(appdatanames),
    rmappdata(hndl,appdatanames{i});
end;


fprintf('Shutting down program\n');

closereq;

close force all;

end



%***********************************
% keypress_callback
%***********************************


function keypress_callback(src,evnt, hndl)
%keyPressFcn automatically takes in two inputs
%src is the object that was active when the keypress occurred
%evnt stores the data for the key pressed
% arg1 is the handle to the image panel




k= evnt.Key; %k is the key that is pressed


if strcmp(k,'p')    % go to a specific page
    % open a dialog box
    prompt={'Page number:'};
    name='Goto page';
    numlines=1;
    defaultanswer={'1'};
    pagenum=inputdlg(prompt,name,numlines,defaultanswer);    
    % check if valid page
    pagenum = str2num(cell2mat(pagenum));
    if (pagenum >= 1 && pagenum <= getappdata(hndl,'lastpage')),
        setappdata(hndl,'currpageindx', pagenum);
    end;
    
    
elseif strcmp(k,'pagedown') 
    %don't go down if already at last page
    if (getappdata(hndl,'currpageindx') + 1) > getappdata(hndl,'lastpage'),
        setappdata(hndl,'currpageindx', getappdata(hndl,'lastpage') );
    else
        setappdata(hndl,'currpageindx', getappdata(hndl,'currpageindx') + 1 );
    end;

elseif strcmp(k,'pageup') 
    %don't go up if already at first page
    if (getappdata(hndl,'currpageindx') - 1) < 1,
        setappdata(hndl,'currpageindx', 1);    % first page
    else
        setappdata(hndl,'currpageindx', getappdata(hndl,'currpageindx') - 1 );
    end;


elseif strcmp(k,'home') 
    setappdata(hndl,'currpageindx', 1);    % first page

elseif strcmp(k,'end') 
	setappdata(hndl,'currpageindx',getappdata(hndl,'lastpage') );


end;


updateroiframes(hndl);   


end







%***********************************
% mainframe_callback
%***********************************

% for handling mouse clicks in main figure, outside of images
function mainframe_callback(src,evnt, hndl)



seltype = get(src,'SelectionType');

if strcmp(seltype,'normal'),
    % nothing yet
    % useful for debugging
%    fprintf('No functionality yet for left-click\n');
%    beep;
elseif strcmp(seltype,'alt')
    % the options menu
	options_dialog([],[], hndl);

elseif strcmp(seltype,'extend')
    % the options menu
%    fprintf('No functionality yet for shift-left-click\n');
%    beep;
    
else
	fprintf('Some error in seltype %s in mainframe_callback\n',seltype);
    beep; pause(0.1); beep; pause(0.1); beep; pause(0.1); beep

end;




end




%***********************************
% image_mouseover_callback
%***********************************

% callback for mouse button over an image in screen
function image_mouseover_callback(src,eventdata, hIm, hndl)
% hIm is the handle to the image clicked on
% the unique image number is in UserData
%
% here do the pulldown to select
% left click to select an image and add it to SETTINGS.selectedimages
% right click to select and pull up attributes dialog

doDebug = 0;


% see if it's a regular mouse click or being passed over from a menu button
if (getappdata(hndl,'selectallxfer') == 1),   % called due to Select All menu
    seltype = 'extend';
    isSel = 'off';

else % called due to mouse click
    imgnum = get(hIm,'UserData');  % which roi number
    imdat = get(hIm,'cdata');      % the data in the image

    % bring up the selection menu for whatever: e.g., attribute of whatever type
    %seltype = get(get(src,'parent'),'selectiontype')
    seltype = get(gcbf,'selectiontype'); % was gcf
    isSel = get(hIm,'selected');
end;



if (doDebug), fprintf('seltype = %s\n',seltype); end;





% LEFTMOUSE  or <SHIFT-LEFTMOUSE / BOTHMOUSE>
if ( strcmp(seltype,'normal') || strcmp(seltype,'extend')),
    % normal: select this roi or unselect if selected
    % extended: select all rois in frame

    if (strcmp(seltype,'extend')),
        if (doDebug), fprintf('extended\n'); end;
        % if this is an extended mouse, make hIm an array of all handles in window
        % img handles for all in current view are in SETTINGS.h_im
        hIm = getappdata(hndl,'h_im');
    end;

    selectedimages = getappdata(hndl,'selectedimages');
    if (strcmp(isSel,'off')),
        if (doDebug), fprintf('normal: selected was off\n'); end;

        
        for j = 1:length(hIm),
            % then select all images now in list
            set(hIm(j),'selected','on');

            imdat = get(hIm(j),'cdata');      % the data in the image
            selectedimages = unique([getappdata(hndl,'selectedimages') get(hIm(j),'UserData')]) ; % in case it's already selected
            imdat(:,:,3) = 0;
            set(hIm(j),'cdata',imdat);   % color it to show selected (zero out final color column)
        end;
        
        
    else
        if (doDebug), fprintf('normal: selected was on\n'); end;
        % then delect this image
        set(hIm,'selected','off');
        % remove this roi from list
        [c, unselect, ab] = intersect(selectedimages, imgnum);
        selectedimages(unselect) = [];
        imdat(:,:,3) = imdat(:,:,2);
        set(hIm,'cdata',imdat);   % color it to show selected
    end;
    setappdata(hndl,'selectedimages',selectedimages);

    
    
% RIGHTMOUSE or CTRL-LEFTMOUSE
elseif strcmp(seltype,'alt')    % CTRL-click left mouse, or right click mouse
	if (doDebug), fprintf('Alt\n'); end;
    
    % regardless of if this image is selected, select it
    set(hIm,'selected','on');
	
    selectedimages = getappdata(hndl,'selectedimages');
    selectedimages = unique([selectedimages imgnum]); % in case it's already selected
    setappdata(hndl,'selectedimages',selectedimages);

    imdat(:,:,3) = 0;
    set(hIm,'cdata',imdat);   % color it to show selected
    
    
    % then open the attribute dialog box, operating on the first keyname in SETTINGS.keyname.list
    keynames = getappdata(hndl,'keynames');
    attribute_dialog(hIm, keynames.list{1}, hndl ); % send it the handle of the current image
    
    
else
	errorHandler('image_mouseover_callback -> Error in seltype\n');
    
end;






% in 2007b there is an issue with focus moving from button to button. use a newer version of Matlab
% set(arg1,'enable','off');  % this little trick to get the uicontrol to release focus
% drawnow;
% set(arg1,'enable','on');
% set(0,'CurrentFigure',SETTINGS.h_main);

end






%***********************************
% image_select_all
%***********************************

% for selecting all imgs in screen
% an ugly hack b/c the shift-leftmouse extend callback won't work ??
function image_select_all(src,evnt, hndl)


setappdata(hndl, 'selectallxfer', 1); % use SETTINGS to notify the callback this is special

image_mouseover_callback(0, 0, 0, hndl);

% for j=1:length(SETTINGS.h_im),
%     image_mouseover_callback(0,0,SETTINGS.h_im(j), hndl);
% end;

setappdata(hndl, 'selectallxfer', 0);

% remove focus from the button



end






function generate_roitable(hndl)


    
% go through all the roi entries and calculate where on the page they will go, & newlines, & newpages
xcum = 0;   % cumulative location of rois in x axis (left to right)
ycum = 0;   % cumulative location of rois in y axis (top to bottom)
yrowmax = 0;    % maximum height of the rois in a row
pagenum = 1;
fig_pos = get(hndl,'position'); %getappdata(hndl,'position');


% this should do the calcs only for those rois of interest (filtered according to whatever is to be viewed)
% the outputs are:
% SETTINGS.xdata & SETTINGS.ydata, of length SETTINGS.images_to_display
% SETTINGS.page of length SETTINGS.images_to_display
% SETTINGS.lastpage, length one

% erase the previous xdata, ydata and page arrays if they exist
len = length(getappdata(hndl,'page'));
if (len > 0),
    setappdata(hndl,'xdata', []);
    setappdata(hndl,'ydata', []);
    setappdata(hndl,'page', []);
end;



for j = 1:length(getappdata(hndl,'images_to_display')),
    % remember: i refers to the indices in the original adc file, j is the index in the list of images to be displayed
    tmpvar = getappdata(hndl,'images_to_display');
    i = tmpvar(j); % the imagenum of the jth roi in this index list roi_indices
    
    tmpvar = getappdata(hndl,'xsize');
    x = tmpvar(i); 
    tmpvar = getappdata(hndl,'ysize');
    y = tmpvar(i); % size of this roi

    if (ycum + y <= fig_pos(4) && xcum + x <= fig_pos(3)), % we can add this roi to the same row (x) on the same page (y)
        tmpvar = getappdata(hndl,'xdata');
        tmpvar(j,:) = [xcum+getappdata(hndl,'border') xcum+x];
        setappdata(hndl,'xdata',tmpvar);
        tmpvar = getappdata(hndl,'ydata');
        tmpvar(j,:) = [ycum+getappdata(hndl,'border') ycum+y];
        setappdata(hndl,'ydata',tmpvar);
        
        xcum = xcum + x;
        if y > yrowmax, 
            yrowmax = y; 
        end;
        
    % we might need to move to the same row
    elseif (ycum + y + yrowmax <= fig_pos(4)), % if the roi will fit on the next row, under the yrowmax in this row...
        xcum = 0;
        ycum = ycum + yrowmax;

        tmpvar = getappdata(hndl,'xdata');
        tmpvar(j,:) = [xcum+getappdata(hndl,'border') xcum+x];
        setappdata(hndl,'xdata',tmpvar);
        tmpvar = getappdata(hndl,'ydata');
        tmpvar(j,:) = [ycum+getappdata(hndl,'border') ycum+y];
        setappdata(hndl,'ydata',tmpvar);
%        SETTINGS.xdata(j,:) = [xcum+SETTINGS.border xcum+x];
%        SETTINGS.ydata(j,:) = [ycum+SETTINGS.border ycum+y];

        xcum = xcum + x;
        yrowmax = y;  % now the new yrowmax is this current y size
        
    else    % it's time for a new page
        xcum = 0; ycum = 0;

        tmpvar = getappdata(hndl,'xdata');
        tmpvar(j,:) = [xcum+getappdata(hndl,'border') xcum+x];
        setappdata(hndl,'xdata',tmpvar);
        tmpvar = getappdata(hndl,'ydata');
        tmpvar(j,:) = [ycum+getappdata(hndl,'border') ycum+y];
        setappdata(hndl,'ydata',tmpvar);
%        SETTINGS.xdata(j,:) = [xcum+SETTINGS.border xcum+x];
%        SETTINGS.ydata(j,:) = [ycum+SETTINGS.border ycum+y];

        xcum = xcum + x;
        yrowmax = y;  % now new yrowmax is this current y size
        pagenum = pagenum + 1;
        
    end;

    tmpvar = getappdata(hndl,'page');
    tmpvar(j) = pagenum; % remember to use j when counting images in this series of frames
    setappdata(hndl,'page',tmpvar);
    
end;

setappdata(hndl,'lastpage', pagenum);


end





function updateroiframes(hndl)

% the inputs from SETTINGS = generate_roitable(SETTINGS) are:
% SETTINGS.xdata & SETTINGS.ydata, of length SETTINGS.images_to_display
% SETTINGS.page of length SETTINGS.images_to_display
% SETTINGS.lastpage, length one

% get current figure focus
currfocus = gcf;
figure(hndl);   % to make sure focus is in main window, regardless of where called from



% need to get rid of the old buttons to paint the new ones
h_im = getappdata(hndl,'h_im');
h_txt = getappdata(hndl,'h_txt');
len = length(h_im);
if (len > 0),
    for i = len:-1:1,
        delete(h_im(i));
        h_im(i) = [];
        delete(h_txt(i));
        h_txt(i) = [];
    end;
end;


% find all the rois on the page to display
rois_in_frame = find(getappdata(hndl,'page') == getappdata(hndl,'currpageindx'));   % which indices in the SETTINGS.page array match this page

fig_pos = get(hndl,'position');

images_to_display = getappdata(hndl,'images_to_display');
xsize = getappdata(hndl,'xsize');
ysize = getappdata(hndl,'ysize');
imgnum = getappdata(hndl,'imgnum');
xdata = getappdata(hndl,'xdata');
ydata = getappdata(hndl,'ydata');
trigger = getappdata(hndl,'trigger');
attributes = getappdata(hndl,'attributes');
attrib = getappdata(hndl,'attrib');
startbyte = getappdata(hndl,'startbyte');


for j = 1:length(rois_in_frame);    % the number of images to be painted in the frame; indices for h_im, h_txt
    k = rois_in_frame(j);   % the value needed to use with SETTINGS.xdata, ydata, page
    i = images_to_display(k);  % the actual image index of the image being referenced here

    position = startbyte(i);
    fseek(getappdata(hndl,'fid'), position, -1);
    data = fread(getappdata(hndl,'fid'), xsize(i).*ysize(i), 'ubit8');

    imagedat = reshape(data, xsize(i), ysize(i));

    if (xsize(i) > 0),
        h_im(j) = uicontrol('Style', 'pushbutton', ...
            'Position', [xdata(k,1) fig_pos(4) - ydata(k,1) - ysize(i) ...
            xdata(k,2) - xdata(k,1) ydata(k,2) - ydata(k,1) ] );

        % assigning callbacks and enabling image
        set(h_im(j),'ButtonDownFcn', {@image_mouseover_callback, h_im(j), hndl});
        set(h_im(j),'callback',{@image_mouseover_callback, h_im(j), hndl});
        set(h_im(j),'Enable','on');    % to get the left mouse button to work too.
        
        
        cmin = min(min(imagedat)); cmax = max(max(imagedat));
        levels = 64;
        cdata = grayslice(imagedat,linspace(cmin, cmax, levels));

        set(h_im(j),'cdata',ind2rgb(cdata',colormap(gray)));

        % stuff the attributes into the tooltip string
        str = [];
        if (~isempty(attributes{i})),

            tmpval = attributes{i};
            to_omit = [];
            % remove the entries in tempval that don't have 'true' for display in SETTINGS.attrib.keyname(i,2)
            for r = 1:length(tmpval),
                ret = textscan(tmpval{r},'%s%d','delimiter','=');
                for s = 1:length(attrib.keynames),
                    if (strcmp(attrib.keynames{s,1},char(ret{1}) )  && ~attrib.keynames{s,2}),
                        to_omit = [to_omit r];
                        break;
                    end;
                end;
            end;
            tmpval(to_omit) = [];
            str = sprintf('%s\n',tmpval{1:length(tmpval)});
        end;
        set(h_im(j),'tooltipstring', str );
        set(h_im(j),'UserData',imgnum(i));    % so that each uicontrol itself will hold the unique index of this image
        
        % make it selected if it was selected in a prior frame
        if ( intersect(getappdata(hndl,'selectedimages'), imgnum(i) ) ),
            set(h_im(j),'selected', 'on');            
        end;
        
        
        h_txt(j) = uicontrol('Style', 'text', 'String', num2str(trigger(i)),...
            'Position', [xdata(k,1),fig_pos(4) - ydata(k,1) - 10, 30 10], ...
            'foregroundcolor','b','backgroundcolor','w');

        
        % if to Hide Sorted, make it inactive if it has a taxon value other
        % than unsorted lg or unsorted small
        if ( get_option_status('Hide sorted', hndl) == 1),
            val = get_attrib(imgnum(i), 'taxon', hndl);
            if ( ~isempty(val) && ~strcmp(val,'unsorted_small') && ~strcmp(val, 'unsorted_large') ),
                set(h_im(j),'visible','off');
            end;
        end;
        
    else
        h_im(j) = uicontrol('style','frame','visible','off');    %some invisible text somewhere; a dummy handle
        h_txt(j) = uicontrol('style','frame','visible','off');
    end;

end;

setappdata(hndl,'h_im',h_im);
setappdata(hndl,'h_txt',h_txt);

set(hndl,'name',[fullfile(getappdata(hndl,'path'), getappdata(hndl,'file')) sprintf('   page %d of %d', getappdata(hndl,'currpageindx'),getappdata(hndl,'lastpage'))] );

% go back to figure that had focus before the update
figure(currfocus);

end






function importIFCBdata(hndl)


% construct the proper fully qualified file names for roi, adc, and hdr files
file = getappdata(hndl,'file');
path = getappdata(hndl,'path');
froot = file(1:findstr(file, '.')-1);
%fname = fullfile(SETTINGS.path, [froot '.adc']);
%hdrname = [fname(1:end-3) 'hdr'];

% and for the atr file. is expecting 'typical' IFCB folder structure
indxs = strfind(getappdata(hndl,'path'),filesep); % where are the file seps?

setappdata(hndl,'atrpath', [path(1:indxs(end-1)) 'attribs' filesep] );
% if this folder doesn't exist, create it
if (exist(getappdata(hndl,'atrpath'),'dir') == 7),
    fprintf('attribs folder found at %s\n',getappdata(hndl,'atrpath'));
elseif (exist(getappdata(hndl,'atrpath'),'dir') == 0),
    % create the folder
    [SUCCESS,MESSAGE,MESSAGEID] = mkdir(getappdata(hndl,'atrpath'));
    if SUCCESS ~= 1,
        errordlg(sprintf(MESSAGE), ['mkdir error ' MESSAGEID]);
        pause(10);
        fclose all;
        closereq;
        return;
    end;
else
    % issue an error
    errordlg(sprintf('Error findng or opening the attribs folder'), 'Folder error');
	pause(10);
    fclose all;
    closereq;
    return;
end;



%check to see which format we are using for input file
file = getappdata(hndl,'file');
if (strcmp(file(1:5),'IFCB8') == 1),
    setappdata(hndl,'inputfmt', 'IFCB8');
elseif (strcmp(file(end-10:end-4),'IFCB008') == 1),
    setappdata(hndl,'inputfmt', 'IFCB8');
elseif (strcmp(file(end-10:end-7),'IFCB') == 1),
    setappdata(hndl,'inputfmt', 'IFCB015');
else
    errordlg(sprintf('Error in determining input file format'), 'Input data error');
	pause(10);
    fclose all;
    closereq;
    return;
end;




% first open the roi file for reading only
setappdata(hndl,'fid', fopen(fullfile(getappdata(hndl,'path'), [froot '.roi']),'rb') );  % open the roi file to read the roi pixel data

fprintf('Opening IFCB file set for %s\n',fullfile(getappdata(hndl,'path'), [froot '.roi']) );

% zero out any ADC data that may have existed before
tmp = getappdata(hndl,'adcdata');
if (~isempty(tmp)),
%    rmappdata(hndl,{'adcdata','num_imgs','imgnum','xsize','ysize','trigger','startbyte','xdata','ydata'}); 

    errordlg(sprintf('Should not get to this point in importIFCBdata\n'), 'Input data error');
end;
clear tmp;

% now load the ADC data using the right ADC file format
setappdata(hndl,'adcdata', load(fullfile(getappdata(hndl,'path'), [froot '.adc']) ) );

adcdata = getappdata(hndl,'adcdata');
tmpval = size(adcdata); 
setappdata(hndl,'num_imgs', tmpval(1) );

setappdata(hndl,'imgnum', 1:getappdata(hndl,'num_imgs'));  % the unique identifier of each roi in this file

setappdata(hndl,'trigger', adcdata(:,1) );   % the trigger that captured this roi
if (strcmp(getappdata(hndl,'inputfmt'),'IFCB8')),
    setappdata(hndl,'xsize', adcdata(:,12) );
    setappdata(hndl,'ysize', adcdata(:,13) ); %x and y sizes of each image in streamed file, from vb_roi_...
    setappdata(hndl,'startbyte', adcdata(:,14) );
elseif (strcmp(getappdata(hndl,'inputfmt'),'IFCB015')),
    setappdata(hndl,'xsize', adcdata(:,16) );  
    setappdata(hndl,'ysize', adcdata(:,17) ); %x and y sizes of each image in streamed file, from vb_roi_...
    setappdata(hndl,'startbyte', adcdata(:,18) );
end;



setappdata(hndl,'xdata', zeros(getappdata(hndl,'num_imgs'),2) );   % for passing to imagesc each time there is a plot
setappdata(hndl,'ydata', zeros(getappdata(hndl,'num_imgs'),2) );   

% zero out any hdr file info
% now grab what is needed from the hdr file
%fullfile(SETTINGS.path, [froot '.hdr'])


% zero out any attribute data that may have existed before
if (isappdata(hndl,'attributes')), rmappdata(hndl,'attributes'); end;



% does the atr file exist already; if not, create it
setappdata(hndl,'atrname', [froot '.atr'] );
d = dir(fullfile(getappdata(hndl,'atrpath'),getappdata(hndl,'atrname') ));

% if there was a file, read its data into SETTINGS
if (~isempty(d)),
    if (length(d) == 1), % a single atr file that matches
        read_atr_file(hndl);
    else,
        errstr = 'Multiple matching ATR files found.';
        errordlg(errstr, 'ATR file?');
        errorHandler(errstr);
        closereq;
    end;
    
else,   % no atr file found
    ButtonName = questdlg('No matching ATR file found. Create one (YES) or exit (NO)?', ...
        'Create ATR file?', 'Yes', 'No', 'No');
    switch ButtonName,
        case 'Yes',
            create_atr_file([],[],hndl);    % will get atr name and path from appdata
            read_atr_file(hndl);
        case 'No',
            closereq;
    end % switch
end;




% display all images, initially
setappdata(hndl,'images_to_display', 1:getappdata(hndl,'num_imgs') ) ;


end



function read_atr_file(hndl)

% the attributes will live in a structure within SETTINGS, e.g.,
%   SETTINGS.attributes(i) as a string of key-value pairs separated by commas
%
% the atr file itself will be a csv file of key-variable pairs for each entry in the adc file


% open the atr file and read in all key-value pairs, & store in SETTINGS.attributes(i)
fid = fopen(fullfile(getappdata(hndl,'atrpath'),getappdata(hndl,'atrname') ),'rt');

% make sure that all the rois in adc file have corresponding attributes, or []
% all entries will at least have a roival field
attrib = getappdata(hndl,'attrib');
attrib.keynames = [];
setappdata(hndl,'attrib',attrib);



for i = 1:getappdata(hndl,'num_imgs'),
    m = fgetl(fid);
    if (m == -1),   % end of line encountered, throw a fit
        uiwait(msgbox('The *.atr file does not have the same number of entries as the *adc file.\nQuitting','Error','modal'));
        guiclosereqestfcn([],[], hndl);
    end;
    
    % this checking may be less than useful
    % otherwise check to see that roinum in atr file is same as roinum in hdr file, & proceed
    s = textscan(m,'%s','delimiter',',');
	attributes = getappdata(hndl,'attributes');
    if (isempty(attributes)),
        attributes = s; % just stuff the whole thing in here without sorting
    else,
        attributes(i) = s; % just stuff the whole thing in here without sorting
    end;
    setappdata(hndl,'attributes',attributes);
    
    %generate_keynames;
    attrib = getappdata(hndl,'attrib');
    for j = 1:length(s{1}),
        rstr = s{1};
        ret = textscan(rstr{j},'%s%d','delimiter','=');
        attrib.keynames = [attrib.keynames ret{1}];
    end;
    attrib.keynames = unique(attrib.keynames);
    setappdata(hndl,'attrib',attrib);
end;

fclose(fid);




% now sort SETTINGS.attrib.keynames according to the order specified in SETTINGS.keyname_order
% e.g., see top of this program, then alphabetical subsequently for entries not in keyname_order
% keyname_order = { ...
%     'imgnum', true; 'lat', false; 'lon', false; 'station', false; 'cast', false; 'btl', false; ...
%     'mlsampled', false; 'taxon', true; 'species', true; 'morpho', true  };

tmp_keynames = attrib.keynames;
attrib.keynames = {};
indx = 1;
to_omit = [];

keyname_order = getappdata(hndl,'keyname_order');

for i = 1:length(keyname_order),
    for j = 1:length(tmp_keynames),
        
        if (strcmp(keyname_order{i},tmp_keynames{j} ) ),
            attrib.keynames(indx,1) = tmp_keynames(j);
            attrib.keynames{indx,2} = keyname_order{i,2};
            indx = indx+1;
            to_omit = [to_omit j];
            break;
        end;
    end;
end;    % here done with finding all of original SETTINGS.attrib.keynames that are in SETTINGS.keyname.order


% delete those that were found to match
tmp_keynames(to_omit) = [];
% add these to the structure, along with "true" to display
for i = 1:length(tmp_keynames),
    tmp_keynames(i,2) = true;
end;
attrib.keynames = [attrib.keynames tmp_keynames];
setappdata(hndl,'attrib',attrib);


% generate some attrib to merge defaults with what is read in input data files
% attrib.<keyname>.name and attrib.<keyname>.display


keynames = getappdata(hndl,'keynames');

for i = 1:length(keynames.list),
    generate_attributes_list(keynames.list{i}, hndl);
end;




end




function generate_attributes_list(keyname, hndl)
% sort the attributes and generate the attribnames list
% here 'keyname' is a string for which attribute to look for, e.g., keyname is "taxon"
% for this function, needs to be stored as strings
%global SETTINGS;


len = length(getappdata(hndl,'attributes'));     % how many entries have attributes listed

% there is probably a quicker way to do this
tmp_attribnames = [];   % need to define it first
k = 1;
attributes = getappdata(hndl,'attributes');
for i = 1:len,  % crank through them and determine the unique ones, for 'attrib'
    
    tmp = attributes{i};
    for j = 1:length(tmp),  % go through the various key-value pairs in this entry: not all the same length
        indx = strfind(tmp{j}, [keyname '='] );
        if ~isempty( indx ),    % this one has a matching key entry in it
            tmp_attribnames{k} = tmp{j}(length(keyname)+2:end);
            k = k + 1;
        end;
    end;
end;


attrib = getappdata(hndl,'attrib');

% these are the sorted, unique attribute names for key "keyname"
eval(['attrib.' keyname '.name = unique(tmp_attribnames);' ]);

% add to this list any default list for this keyname
%eval ([ 'SETTINGS.attrib.' keyname '.name = unique( [ SETTINGS.attrib.' keyname '.name SETTINGS.' keyname '] ); ']);
eval ([ 'attrib.' keyname '.name = unique( [ attrib.' keyname '.name getappdata(hndl,''' keyname ''')] ); ']);

% some initial niceties for displaying images of this keyname
%eval(['for i = 1:length(attrib.' keyname '.name), attrib.' keyname '.display(i) = true; end; ']);
eval(['for i = 1:length(attrib.' keyname '.name), attrib.' keyname '.display(i) = true; end; ']);


setappdata(hndl,'attrib',attrib);


end




% creates a blank atr file
function create_atr_file(src,evnt,hndl)

%attributes = getappdata(hndl,'attributes');
attributes = cell(1);

adcdata = getappdata(hndl,'adcdata');
xsize = getappdata(hndl,'xsize');
for i=1:getappdata(hndl,'num_imgs'),
    % size of roi: small or large for initial sorting
    if (xsize(i) > getappdata(hndl,'roismallsizethresh')),
        sizestr = 'unsorted_large';
    else
        sizestr = 'unsorted_small';
    end;
    s = textscan(sprintf('imgnum=%d,lat=,lon=,station=,cast=,btl=,mlsampled=,taxon=%s',adcdata(i,1),sizestr), ...
        '%s','delimiter',',');
    attributes(i) = s; % just stuff the whole thing in here without sorting
end;
setappdata(hndl,'attributes',attributes);

write_atr_file([],[],hndl);

end





function write_atr_file(src,evnt, hndl)
% where the atr file is rewritten back out (overwritten)

fprintf(sprintf('Saving data to *.atr file %s at %s\n',getappdata(hndl,'atrname'),datestr(now)) );
h = msgbox(sprintf('Saving data to *.atr file\n%s',getappdata(hndl,'atrname')),'Saving data','modal');
% open the atr file and read in all key-value pairs, & store in SETTINGS.attributes(i)
fout = fopen(fullfile(getappdata(hndl,'atrpath'),getappdata(hndl,'atrname')),'wt');

attributes = getappdata(hndl,'attributes');
for i=1:getappdata(hndl,'num_imgs'),
    
    tmpval = attributes{i};
    str = sprintf('%s,',tmpval{1:length(tmpval)});
    fprintf(fout,'%s\n',str);
   
end;

fclose(fout);

% clear the messagebox
delete(h);

end




% callback function to occur when ATR file autosave timer fires
function atr_timer_update(src,evnt, hndl)
    
    stop(getappdata(hndl,'atrfilesavetimer'));
    fprintf('ATR file autosave: ');
    write_atr_file([],[],hndl);

    % reset the timer
    start(getappdata(hndl,'atrfilesavetimer'));

end











function menu_export_images(src,evnt, hndl)
% used to export the selected images to a TIFF file


% this can be done only if image processing toolbox is installed
    
% prompt for folder to put tiffs
outdir = uigetdir(getappdata(hndl,'tiff_outdir'));
if outdir == 0,
    return;
else
    setappdata(hndl,'tiff_outdir', outdir);
end

% determine the root name for these files
file = getappdata(hndl,'file');
froot = file(1:findstr(file, '.')-1);

% selected images is by imgnum, but SETTINGS.h_im is only those in window
xsize = getappdata(hndl,'xsize');
ysize = getappdata(hndl,'ysize');
h_im = getappdata(hndl,'h_im');
startbyte = getappdata(hndl,'startbyte');
selectedimages = getappdata(hndl,'selectedimages');
for j = 1:length(selectedimages)
    
    
    % crank through each selected one, exporting it
    for k = 1:length(h_im),
        if ( selectedimages(j) == get(h_im(k),'UserData') ),
            indx = k;
            break;
        end;
    end;
    
    i = get(h_im(indx), 'UserData');    % get the imagenum
    position = startbyte(i);
    fseek(getappdata(hndl,'fid'), position, -1);
    data = fread(getappdata(hndl,'fid'), xsize(i).*ysize(i), 'ubit8');
    imagedat = reshape(data, xsize(i), ysize(i));
    
    cmin = min(min(imagedat)); cmax = max(max(imagedat));
    levels = 64;
    cdata = grayslice(imagedat,linspace(cmin, cmax, levels));
    
    tiffname = fullfile(getappdata(hndl,'tiff_outdir'), [froot sprintf('_%04d',i) '.tif']);
    if ~isempty(imagedat),
        imwrite(uint8(imagedat'), tiffname, 'tiff','compression','none');
    end;
    
end
    


setappdata(hndl,'selectedimages', []);   % zero out selected images list
updateroiframes(hndl);                % redraw the window
drawnow;


end















%***************************************************************************
%
%
%***************************************************************************





function bout=grayslice(I,z)
%GRAYSLICE Create indexed image from intensity image by thresholding.
%   X=GRAYSLICE(I,N) thresholds the intensity image I using threshold values
%   1/n, 2/n, ..., (n-1)/n, returning an indexed image in X.
%
%   X=GRAYSLICE(I,V), where V is a vector of values between 0 and 1, thresholds
%   I using the values of V as thresholds, returning an indexed image in X.
%
%   You can view the thresholded image using IMSHOW(X,MAP) with a colormap of
%   appropriate length.
%
%   Class Support
%   -------------  
%   The input image I can uint8, uint16, int16, single or double, and must be
%   nonsparse. Note that the threshold values are always between 0 and 1, even
%   if I is of class uint8 or uint16.  In this case, each threshold value is
%   multiplied by 255 or 65535 to determine the actual threshold to use.
%
%   The class of the output image X depends on the number of threshold values,
%   as specified by N or length(V). If the number of threshold values is less
%   than 256, then X is of class uint8, and the values in X range from 0 to N or
%   length(V). If the number of threshold values is 256 or greater, X is of
%   class double, and the values in X range from 1 to N+1 or length(V)+1.
%
%   Example
%   -------
%   Use multilevel thresholding to enhance high intensity areas in the image.
%
%       I = imread('snowflakes.png');
%       X = grayslice(I,16);
%       figure, imshow(I), figure, imshow(X,jet(16))
%
%   See also GRAY2IND.

%   Copyright 1993-2006 The MathWorks, Inc.


narginchk(1,2);
validateattributes(I,{'double','uint8','uint16','int16','single'},{'nonsparse'}, ...
              mfilename,'I',1);

if nargin == 1 
  z = 10; 
elseif ~isa(z,'double')
  z = double(z);
end

% Convert int16 data to uint16.
if isa(I,'int16')
  I = int16touint16mex(I);
end

range = getrangefromclass(I);

if ( (numel(z) == 1) && ((round(z)==z) || (z>1)) )
   % arg2 is scalar: Integer number of equally spaced levels.
   n = z; 
   if isinteger(I)
       z = range(2) * (0:(n-1))/n; 
   else % I is double or single
      z = (0:(n-1))/n;
   end
else
   % arg2 is vector containing threshold levels
   n = length(z)+1;
   if isinteger(I)
       % uint8 or uint16
      zmax = range(2);
      zmin = range(1);
   else
       % double or single
      maxI = max(I(:));
      minI = min(I(:));
      % make sure that zmax and zmin are double
      zmax = max(1,double(maxI));
      zmin = min(0,double(minI));
   end
   newzmax = min(zmax,sort(z(:)));
   newzmax = newzmax';
   newzmax = max(zmin,newzmax);
   z = [zmin,newzmax]; % sort and threshold z
end

% Get output matrix of appropriate size and type
if n < 256
   b = repmat(uint8(0), size(I));  
else 
   b = zeros(size(I)); 
end

% Loop over all intervals, except the last
for i = 1:length(z)-1
   % j is the index value we will output, so it depend upon storage class
   if isa(b,'uint8') 
      j = i-1; 
   else 
      j = i;  
   end
   d = find(I>=z(i) & I<z(i+1));
   if ~isempty(d), 
      b(d) = j; 
   end
end

% Take care of that last interval
d = find(I >= z(end));
if ~isempty(d)
   % j is the index value we will output, so it depend upon storage class
   if isa(b, 'uint8'), 
      j = length(z)-1; 
   else 
      j = length(z); 
   end
   b(d) = j; 
end

if nargout == 0
   imshow(b,jet(n))
   return
end
bout = b;


end


