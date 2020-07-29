/**
 Copyright (C) 2018-2020 by Autodesk, Inc.
 All rights reserved.

 3D additive printer post configuration.

 $Revision: 42682 9471a22a72e5b6a8be7a1bf341716ac0009d9847 $
 $Date: 2020-03-09 03:36:19 $

 FORKID {A316FBC4-FA6E-41C5-A347-3D94F72F5D06}
 */

description = "Machinekit";
vendor = "GaOlSt";
vendorUrl = "http://www.machinekit.io";
legal = "";
certificationLevel = 2;
minimumRevision = 45633;
debugMode = true;

longDescription = "Simple post to export toolpath for generic FFF Machine in gcode format";

extension = "ngc";
setCodePage("ascii");

capabilities = CAPABILITY_ADDITIVE;
tolerance = spatial(0.05, MM);
highFeedrate = (unit == MM) ? 6000 : 236;


// user-defined properties
properties = {
    useVelocityExtrusion: false, // enable velocity extrusion mode
    velocityExtrusionTolerance: 0.001,
    enableFeedHold: true, // enable velocity extrusion mode
    tolerance: 0.05,
    enableFirmareRetraction: false,
    retractLengthIndex: 0.5,
    retractVelocityIndex: 26,
    startGcode: "M106t1p200;",
    endGcode: ";"
};

// user-defined property definitions
propertyDefinitions = {
    useVelocityExtrusion: {title:"Velocity extrusion", description:"Enable velocity extrusion mode", group:1, type:"boolean"},
    velocityExtrusionTolerance:{title:"Velocity extrusion tolerance", description:"Velocity extrusion deviation tolerance", group:1, type:"number"},
    tolerance: {title:"Path blending Tolerance", description:"Path blending tolerance in mm", group:2, type:"number"},
    enableFirmareRetraction: {title:"Firmware Retraction", description:"Enable firmware retract commands", group:3, type:"boolean"},
    enableFeedHold: {title:"Feed hold", description:"Enable feed-hold on retract/pre-charge", group:3, type:"boolean"},
    retractLengthIndex: {title:"Retraction length", description:"How much filament should be retracted", group:3, type:"number"},
    retractVelocityIndex: {title:"Retraction velocity", description:"Speed of retraction", group:3, type:"number"},
    startGcode: {title:"Start G-Code", description:"G-Code executed on start", group:4, type:"string"},
    endGcode: {title:"End G-Code", description:"G-Code executed on end", group:4, type:"string"}


};

// needed for range checking, will be effectively passed from Fusion
var printerLimits = {
    x: {min: 0, max: 300.0}, //Defines the x bed size
    y: {min: 0, max: 300.0}, //Defines the y bed size
    z: {min: 0, max: 300.0} //Defines the z bed size
};

var extruderOffsets = [[0, 0, 0], [0, 0, 0]];
var lastPosition = {x: 0, y: 0, z: 0};
var activeExtruder = 0;  //Track the active extruder.
var extrudedDistance = 0;
var extruderFilamentParams =[[0,0],[0,0]]; // keep FilamentDiameter and crossSection of extruders
var lastExtrusionRate = 0;
var extrusionFeed;

var xyzFormat = createFormat({decimals: (unit == MM ? 3 : 4)});
var xFormat = createFormat({decimals: (unit == MM ? 3 : 4)});
var yFormat = createFormat({decimals: (unit == MM ? 3 : 4)});
var zFormat = createFormat({decimals: (unit == MM ? 3 : 4)});
var gFormat = createFormat({prefix: "G", width: 1, zeropad: false, decimals: 0});
var mFormat = createFormat({prefix: "M", width: 2, zeropad: true, decimals: 0});
var velocityExtrusionFormat = createFormat({prefix:"M700 P", width: 1, zeropad: false, decimals:4});
var tFormat = createFormat({prefix: "T", width: 1, zeropad: false, decimals: 0});
var feedFormat = createFormat({decimals: (unit == MM ? 0 : 1)});
var integerFormat = createFormat({decimals:0});
var decimalFormat = createFormat({decimals: (unit == MM ? 3 : 4)});
var dimensionFormat = createFormat({decimals: (unit == MM ? 3 : 4), zeropad: false, suffix: (unit == MM ? "mm" : "in")});

var gMotionModal = createModal({force: true}, gFormat); // modal group 1 // G0-G3, ...
var gPlaneModal = createModal({onchange: function () {gMotionModal.reset();}}, gFormat); // modal group 2 // G17-19 //Actually unused
var gAbsIncModal = createModal({}, gFormat); // modal group 3 // G90-91

var xOutput = createVariable({prefix: "X"}, xFormat);
var yOutput = createVariable({prefix: "Y"}, yFormat);
var zOutput = createVariable({prefix: "Z"}, zFormat);
var feedOutput = createVariable({prefix: "F"}, feedFormat);
var aOutput = createVariable({prefix: "A"}, xyzFormat);  // Extrusion length
var sOutput = createVariable({prefix: "S", force: true}, xyzFormat);  // Parameter temperature or speed
var pOutput = createVariable({prefix: "P", force: true}, decimalFormat);  // Parameter vale
var tOutput = createVariable({prefix: "T", force: true}, integerFormat);  // Parameter vale
var qOutput = createVariable({prefix: "Q", force: true}, decimalFormat);  // Parameter vale
var velocityExtrusionOutput= createVariable({},velocityExtrusionFormat);
var firmwareRetractOutput = createVariable({width: 1, zeropad: false, decimals: 0},gFormat);
// Writes the specified block.
function writeBlock() {
    writeWords(arguments);
}


function onOpen() {
    getPrinterGeometry();

    if (programName) {
        writeComment(programName);
    }
    if (programComment) {
        writeComment(programComment);
    }

    var fddddd = getExtruder(1).filamentDiameter;
    writeComment(fddddd)
    var filament_area = Math.pow(getExtruder(1).filamentDiameter,2)*Math.PI/4;
    extruderFilamentParams[0] = [getExtruder(1).filamentDiameter, filament_area];
    writeComment("Printer Name: " + machineConfiguration.getVendor() + " " + machineConfiguration.getModel());
    writeComment("Print time: " + xyzFormat.format(printTime) + "s");
    writeComment("Extruder 1 Material used: " + dimensionFormat.format(getExtruder(1).extrusionLength));
    writeComment("Extruder 1 Material name: " + getExtruder(1).materialName);
    writeComment("Extruder 1 Filament diameter: " + dimensionFormat.format(getExtruder(1).filamentDiameter));
    writeComment("Extruder 2 filament cross area " + dimensionFormat.format(filament_area));
    writeComment("Extruder 1 Nozzle diameter: " + dimensionFormat.format(getExtruder(1).nozzleDiameter));
    writeComment("Extruder 1 offset x: " + dimensionFormat.format(extruderOffsets[0][0]));
    writeComment("Extruder 1 offset y: " + dimensionFormat.format(extruderOffsets[0][1]));
    writeComment("Extruder 1 offset z: " + dimensionFormat.format(extruderOffsets[0][2]));
    writeComment("Max temp: " + integerFormat.format(getExtruder(1).temperature));
    writeComment("Bed temp: " + integerFormat.format(bedTemp));
    writeComment("Layer Count: " + integerFormat.format(layerCount));

    if (hasGlobalParameter("ext2-extrusion-len") &&
        hasGlobalParameter("ext2-nozzle-dia") &&
        hasGlobalParameter("ext2-temp") && hasGlobalParameter("ext2-filament-dia") &&
        hasGlobalParameter("ext2-material-name")
    ) {
        var area = Math.pow(getExtruder(2).filamentDiameter,2)*Math.PI/4;
        extruderFilamentParams[1] = [getExtruder(2).filamentDiameter, area];
        writeComment("Extruder 2 material used: " + dimensionFormat.format(getExtruder(2).extrusionLength));
        writeComment("Extruder 2 material name: " + getExtruder(2).materialName);
        writeComment("Extruder 2 filament diameter: " + dimensionFormat.format(getExtruder(2).filamentDiameter));
        writeComment("Extruder 2 filament cross area " + dimensionFormat.format(area));
        writeComment("Extruder 2 nozzle diameter: " + dimensionFormat.format(getExtruder(2).nozzleDiameter));
        writeComment("Extruder 2 max temp: " + integerFormat.format(getExtruder(2).temperature));
        writeComment("Extruder 2 offset x: " + dimensionFormat.format(extruderOffsets[1][0]));
        writeComment("Extruder 2 offset y: " + dimensionFormat.format(extruderOffsets[1][1]));
        writeComment("Extruder 2 offset z: " + dimensionFormat.format(extruderOffsets[1][2]));


    }

    writeComment("width: " + dimensionFormat.format(printerLimits.x.max));
    writeComment("depth: " + dimensionFormat.format(printerLimits.y.max));
    writeComment("height: " + dimensionFormat.format(printerLimits.z.max));
    writeComment("Count of bodies: " + integerFormat.format(partCount));
    writeComment("Velocity extrusion mode:" + properties.useVelocityExtrusion);
    tolerance = spatial(properties.tolerance, unit);
    if (tolerance) {
        writeComment("Tolerance:" + properties.tolerance);
        writeBlock(gFormat.format(64),pOutput.format(tolerance));
    }
    writeComment("Firmware retraction:" + properties.enableFirmareRetraction);
    writeComment("Version of Fusion: " + getGlobalParameter("version"));
    if (properties.enableFeedHold) {
        writeComment("enable feed-hold on retract/pre-charge");
        writeBlock(mFormat.format(53), pOutput.format(1));
    };
    if (properties.enableFirmareRetraction) {
        writeBlock(mFormat.format(207),pOutput.format(properties.retractLengthIndex),qOutput.format(properties.retractVelocityIndex));
    };
    //enable velocity extrusion support
}

function getPrinterGeometry() {
    machineConfiguration = getMachineConfiguration();

    // Get the printer geometry from the machine configuration
    printerLimits.x.min = 0 - machineConfiguration.getCenterPositionX();
    printerLimits.y.min = 0 - machineConfiguration.getCenterPositionY();
    printerLimits.z.min = 0 + machineConfiguration.getCenterPositionZ();

    printerLimits.x.max = machineConfiguration.getWidth() - machineConfiguration.getCenterPositionX();
    printerLimits.y.max = machineConfiguration.getDepth() - machineConfiguration.getCenterPositionY();
    printerLimits.z.max = machineConfiguration.getHeight() + machineConfiguration.getCenterPositionZ();

    extruderOffsets[0][0] = machineConfiguration.getExtruderOffsetX(1);
    extruderOffsets[0][1] = machineConfiguration.getExtruderOffsetY(1);
    extruderOffsets[0][2] = machineConfiguration.getExtruderOffsetZ(1);
    if (numberOfExtruders > 1) {
        extruderOffsets[1] = [];
        extruderOffsets[1][0] = machineConfiguration.getExtruderOffsetX(2);
        extruderOffsets[1][1] = machineConfiguration.getExtruderOffsetY(2);
        extruderOffsets[1][2] = machineConfiguration.getExtruderOffsetZ(2);
    }
}

function onClose() {
    onImpliedCommand(COMMAND_END);
    writeComment("END OF GCODE");
    writeBlock(mFormat.format(2));

}

function onComment(message) {
    switch (message) {
        case "rapid-dry":
            writeComment(message);
            break;
        default:
            writeComment(message);
    }
}

function onSection() {
    var range = currentSection.getBoundingBox();
    axes = ["x", "y", "z"];
    formats = [xFormat, yFormat, zFormat];
    for (var element in axes) {
        var min = formats[element].getResultingValue(range.lower[axes[element]]);
        var max = formats[element].getResultingValue(range.upper[axes[element]]);
        if (printerLimits[axes[element]].max < max || printerLimits[axes[element]].min > min) {
            error(localize("A toolpath is outside of the build volume."));
        }
    }

    // set unit
    writeBlock(gFormat.format(unit == MM ? 21 : 20));
    writeBlock(gAbsIncModal.format(90)); // absolute spatial co-ordinates
    // writeBlock(mFormat.format(82)); // absolute extrusion co-ordinates

    //homing
    writeRetract(Z); // retract in Z

    //lower build plate before homing in XY
    var initialPosition = getFramePosition(currentSection.getInitialPosition());
    writeBlock(gMotionModal.format(1), zOutput.format(initialPosition.z), feedOutput.format(highFeedrate));

    // home XY
    writeRetract(X, Y);
    if (properties.useVelocityExtrusion) {
        aOutput.format(0);
    } else {
        writeBlock(gFormat.format(92), aOutput.format(0));
    }
}

function onRapid(_x, _y, _z) {
    updateLastPosition();
    var x = xOutput.format(_x);
    var y = yOutput.format(_y);
    var z = zOutput.format(_z);
    if (properties.useVelocityExtrusion && !properties.enableFirmareRetraction) {
        setExtrusionRate(0);
    }
    if (x || y || z) {
        writeBlock(gMotionModal.format(0), x, y, z);
    }
}

function retract() {
    writeBlock(firmwareRetractOutput.format(22));
}

function preCharge() {
    writeBlock(firmwareRetractOutput.format(23));
}

function hypot(a, b) {
    return Math.sqrt(Math.pow(a,2)+Math.pow(b,2));
}

function getExtrusionRate(_x,_y,_z,extrusionDistance) {

    var diffx = _x - lastPosition.x;
    var diffy = _y - lastPosition.y;
    var diffz = _z - lastPosition.z;

    var length = hypot(diffx, diffy);
    if (diffz !== 0) {
        length = hypot(length, diffz);
    }
    var filamentArea = extruderFilamentParams[activeExtruder][1];
    var volume = extrusionDistance * filamentArea;
    if (length == 0) {
        return 0;
    }
    return volume / length;
}

function setExtrusionRate(rate) {
    if (Math.abs(velocityExtrusionOutput.getCurrent() - rate) > properties.velocityExtrusionTolerance) {
        writeBlock(velocityExtrusionOutput.format(rate));
    }
}

function updateLastPosition() {
    lastPosition.x = xOutput.getCurrent();
    lastPosition.y = yOutput.getCurrent();
    lastPosition.z = zOutput.getCurrent();
}

function retract_precharge(extrusionLength) {
    if (properties.enableFirmareRetraction) {
        if (extrusionLength > 0) {
            preCharge();
        } else if (extrusionLength < 0) {
            retract();
        }
    } else {
        if (extrusionLength > 0) {
            writeComment("purge in place");
            writeBlock(mFormat.format(710), pOutput.format(extrusionLength), qOutput.format(feedOutput.getCurrent()));
        } else if (extrusionLength < 0) {
            writeComment("retract in place");
            writeBlock(mFormat.format(710), pOutput.format(Math.abs(extrusionLength)), qOutput.format(-feedOutput.getCurrent()));
        }
    }
}

function onLinearExtrude(_x, _y, _z, _f, _a) {
    if (properties.useVelocityExtrusion) {
        updateLastPosition();
    }
    var x = xOutput.format(_x);
    var y = yOutput.format(_y);
    var z = zOutput.format(_z);
    var f = feedOutput.format(_f);
    var lastExtrusion = aOutput.getCurrent();
    var a = aOutput.format(_a);
    if (!properties.useVelocityExtrusion) {
        if (x || y || z || f || a) {
            writeBlock(gMotionModal.format(1), x, y, z, f, a);
            return;
        }
    } else {
        var extrusionLength = _a - lastExtrusion;
        var onlyExtrusion = !(x || y || z );
        if (onlyExtrusion) {
            retract_precharge(extrusionLength);
        } else if (a) {
            var rate = getExtrusionRate(_x,_y,_z,extrusionLength);
            setExtrusionRate(rate);
            writeBlock(gMotionModal.format(1), x, y, z, f);
        } else if (f) {
            setFeedRate(_f);
        } else {
            writeComment("ERROR in processing, skipping - you should not see this");
        }
    }
}

function onBedTemp(temp, wait) {
    if (wait) {
        writeBlock(mFormat.format(190), pOutput.format(temp));
    } else {
        writeBlock(mFormat.format(140), pOutput.format(temp));
    }
}

function onExtruderChange(id) {
    if (id > 0) {
        error(localize("This printer doesn't support the extruder ") + integerFormat.format(id) + " !");
    }

    if (id < numberOfExtruders) {
        writeBlock(tFormat.format(id));
        activeExtruder = id;
        xOutput.reset();
        yOutput.reset();
        zOutput.reset();
    } else {
        error(localize("This printer doesn't support the extruder ") + integerFormat.format(id) + " !");
    }
}

function onExtrusionReset(length) {
    extrudedDistance = length;
    if (!properties.useVelocityExtrusion) {
        aOutput.reset();
        writeBlock(gFormat.format(92), aOutput.format(length));
    }
}

function onLayer(num) {
    writeComment("Layer : " + integerFormat.format(num) + " of " + integerFormat.format(layerCount));
}

function onExtruderTemp(temp, wait, id) {
    if (id < numberOfExtruders) {
        if (wait) {
            writeBlock(mFormat.format(109), tFormat.format(id), pOutput.format(temp) );
        } else {
            writeBlock(mFormat.format(104), tFormat.format(id) ,pOutput.format(temp) );
        }
    } else {
        error(localize("This printer doesn't support the extruder ") + integerFormat.format(id) + " !");
    }
}

function onFanSpeed(speed, id) {
    writeBlock(mFormat.format(106),tOutput.format(id),pOutput.format(speed))
}

function onPassThrough(text) { var commands = String(text).split(";"); for (text in commands) { writeBlock(commands[text]); } }

function onParameter(name, value) {
    switch (name) {
        //feedrate is set before rapid moves and extruder change
        case "feedRate":
            if (unit == IN) {
                value /= 25.4;
            }
            setFeedRate(value);
            break;
        case "customCommand":
            if (value == "start_gcode") {
                writeComment(value);
                onPassThrough(properties.startGcode);
            } else if (value == "end_gcode") {
                writeComment(value);
                onPassThrough(properties.endGcode);
            }
            break;
        case "machine-config":
            break;
        default:
            writeComment(name + ":" + value);
            break;
        //warning or error message on unhandled parameter?
    }
}

//user defined functions
function setFeedRate(value) {
    feedOutput.reset();
    writeBlock(gFormat.format(1), feedOutput.format(value));
}

function writeComment(text) {
    writeln(";" + text);
}

/** Output block to do safe retract and/or move to home position. */
function writeRetract() {
    if (arguments.length == 0) {
        error(localize("No axis specified for writeRetract()."));
        return;
    }
    var words = []; // store all retracted axes in an array
    for (var i = 0; i < arguments.length; ++i) {
        let instances = 0; // checks for duplicate retract calls
        for (var j = 0; j < arguments.length; ++j) {
            if (arguments[i] == arguments[j]) {
                ++instances;
            }
        }
        if (instances > 1) { // error if there are multiple retract calls for the same axis
            error(localize("Cannot retract the same axis twice in one line"));
            return;
        }
        switch (arguments[i]) {
            case X:
                words.push("X" + xyzFormat.format(machineConfiguration.hasHomePositionX() ? machineConfiguration.getHomePositionX() : 0));
                xOutput.reset();
                break;
            case Y:
                words.push("Y" + xyzFormat.format(machineConfiguration.hasHomePositionY() ? machineConfiguration.getHomePositionY() : 0));
                yOutput.reset();
                break;
            case Z:
                words.push("Z" + xyzFormat.format(0));
                zOutput.reset();
                retracted = true; // specifies that the tool has been retracted to the safe plane
                break;
            default:
                error(localize("Bad axis specified for writeRetract()."));
                return;
        }
    }
    if (words.length > 0) {
        gMotionModal.reset();
        // writeBlock(gFormat.format(28), gAbsIncModal.format(90), words); // retract
        // writeBlock(gAbsIncModal.format(90), words); // retract
    }
}
