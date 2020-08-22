# Fusion 360 Post processor for Machinekit FFF 3D printing
###Post processor currently supports:<br>
####Velocity extrusion<br>
When enabled - Post script will remove all extruder controls (A axis) from G1 moves and replace it with M700 Pxxx, retract/pre-charge will be executed with M710 Pxx Qxx, if Firmware retraction is enabled G22/G23 will be used<br>
When disabled - Post script will generate usual A axis extrusion and Firmware retraction will be ignored.   
####Firmware retraction (on velocity extrusion)<br>
When enabled - Post script will initialize firmware retraction with M207 Pxx Qxx and will analyze extrusion commands, if it will detect reverse extrusion - will replace it with G22, on next positive extrusion will insert G23
####Path blending<br>
When enabled - post script will set Path blending tolerance with command G64 Pxx
####Feed hold
When enabled - will insert M53 P1 in initialization config
####Start/End codes
start_gcode will be inserted after configuration initialization and before heating the bed<br>
end_gcode will be inserted before last M2 command 

#Additional FFF support in Machnekit
http://www.machinekit.io/docs/fdm/fdm-gcode/

#How to install post script in Fusion 360<br>
https://knowledge.autodesk.com/support/fusion-360/learn-explore/caas/sfdcarticles/sfdcarticles/How-to-add-a-Post-Processor-to-your-Personal-Posts-in-Fusion-360.html
