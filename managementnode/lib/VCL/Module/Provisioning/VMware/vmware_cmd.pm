#!/usr/bin/perl -w
###############################################################################
# $Id$
###############################################################################
# Licensed to the Apache Software Foundation (ASF) under one or more
# contributor license agreements.  See the NOTICE file distributed with
# this work for additional information regarding copyright ownership.
# The ASF licenses this file to You under the Apache License, Version 2.0
# (the "License"); you may not use this file except in compliance with
# the License.  You may obtain a copy of the License at
#
#     http://www.apache.org/licenses/LICENSE-2.0
#
# Unless required by applicable law or agreed to in writing, software
# distributed under the License is distributed on an "AS IS" BASIS,
# WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied.
# See the License for the specific language governing permissions and
# limitations under the License.
###############################################################################

=head1 NAME

VCL::Module::Provisioning::VMware::vmware_cmd;

=head1 SYNOPSIS

 my $vmhost_datastructure = $self->get_vmhost_datastructure();
 my $vmware_cmd = VCL::Module::Provisioning::VMware::vmware_cmd->new({data_structure => $vmhost_datastructure});
 my @registered_vms = $vmware_cmd->get_registered_vms();

=head1 DESCRIPTION

 This module provides support for VMs to be controlled using VMware Server 1.x's
 vmware-cmd command via SSH.

=cut

##############################################################################
package VCL::Module::Provisioning::VMware::vmware_cmd;

# Specify the lib path using FindBin
use FindBin;
use lib "$FindBin::Bin/../../../..";

# Configure inheritance
use base qw(VCL::Module::Provisioning::VMware::VMware);

# Specify the version of this module
our $VERSION = '2.00';

# Specify the version of Perl to use
use 5.008000;

use strict;
use warnings;
use diagnostics;

use VCL::utils;

##############################################################################

=head1 PRIVATE OBJECT METHODS

=cut

#/////////////////////////////////////////////////////////////////////////////

=head2 initialize

 Parameters  : none
 Returns     : boolean
 Description : Initializes the vmware_cmd object by by checking if vmware-cmd is
               available on the VM host.

=cut

sub initialize {
	my $self = shift;
	if (ref($self) !~ /VCL::Module/i) {
		notify($ERRORS{'CRITICAL'}, 0, "subroutine was called as a function, it must be called as a class method");
		return;
	}
	
	my $args  = shift;

	# Check to make sure the VM host OS object is available
	if (!defined $args->{vmhost_os}) {
		notify($ERRORS{'WARNING'}, 0, "required 'vmhost_os' argument was not passed");
		return;
	}
	elsif (ref $args->{vmhost_os} !~ /VCL::Module::OS/) {
		notify($ERRORS{'CRITICAL'}, 0, "'vmhost_os' argument passed is not a reference to a VCL::Module::OS object, type: " . ref($args->{vmhost_os}));
		return;
	}

	# Store a reference to the VM host OS object in this object
	$self->{vmhost_os} = $args->{vmhost_os};
	
	# Check if vmware-cmd is available on the VM host
	my $command = 'vmware-cmd';
	my ($exit_status, $output) = $self->vmhost_os->execute($command);
	if (!defined($output)) {
		notify($ERRORS{'WARNING'}, 0, "failed to run SSH command to determine if vmware-cmd is available on the VM host");
		return;
	}
	elsif (grep(/not found/i, @$output)) {
		notify($ERRORS{'DEBUG'}, 0, "vmware-cmd is not available on the VM host, output:\n" . join("\n", @$output));
		return;
	}
	else {
		notify($ERRORS{'DEBUG'}, 0, "vmware-cmd is available on VM host");
	}
	
	notify($ERRORS{'DEBUG'}, 0, ref($self) . " object initialized");
	return 1;
}

#/////////////////////////////////////////////////////////////////////////////

=head2 _run_vmware_cmd

 Parameters  : $vmware_cmd_arguments
 Returns     : array ($exit_status, $output)
 Description : Runs vmware-cmd on the VMware host.

=cut

sub _run_vmware_cmd {
	my $self = shift;
	if (ref($self) !~ /VCL::Module/i) {
		notify($ERRORS{'CRITICAL'}, 0, "subroutine was called as a function, it must be called as a class method");
		return;
	}
	
	my $vmware_cmd_arguments = shift;
	if (!$vmware_cmd_arguments) {
		notify($ERRORS{'WARNING'}, 0, "vmware-cmd arguments were not specified");
		return;
	}
	
	my $vmhost_computer_name = $self->vmhost_os->data->get_computer_short_name();
	
	my $command = "vmware-cmd $vmware_cmd_arguments";
	
	my ($exit_status, $output) = $self->vmhost_os->execute($command);
	if (!defined($output)) {
		notify($ERRORS{'WARNING'}, 0, "failed to run vmware-cmd on VM host $vmhost_computer_name: '$command'");
	}
	else {
		#notify($ERRORS{'DEBUG'}, 0, "executed vmware-cmd on VM host $vmhost_computer_name: '$command'");
		return ($exit_status, $output);
	}
}

#/////////////////////////////////////////////////////////////////////////////

=head2 _get_file_name

 Parameters  : $file_path
 Returns     : string
 Description : Extracts the file name from a file path.

=cut

sub _get_file_name {
	my $self = shift;
	if (ref($self) !~ /VCL::Module/i) {
		notify($ERRORS{'CRITICAL'}, 0, "subroutine was called as a function, it must be called as a class method");
		return;
	}
	
	my $file_path = shift;
	my ($file_name) = $file_path =~ /([^\/]+)$/;
	return $file_name || $file_path;
}

##############################################################################

=head1 API OBJECT METHODS

=cut

#/////////////////////////////////////////////////////////////////////////////

=head2 get_registered_vms

 Parameters  : none
 Returns     : array
 Description : Returns an array containing the vmx file paths of the VMs running
               on the VM host.

=cut

sub get_registered_vms {
	my $self = shift;
	if (ref($self) !~ /VCL::Module/i) {
		notify($ERRORS{'CRITICAL'}, 0, "subroutine was called as a function, it must be called as a class method");
		return;
	}
	
	# Run 'vmware-cmd -l'
	my $vmware_cmd_arguments = "-l";
	my ($exit_status, $output) = $self->_run_vmware_cmd($vmware_cmd_arguments);
	return if !$output;
	
	my @vmx_file_paths = grep(/^\//, @$output);
	notify($ERRORS{'DEBUG'}, 0, "registered VMs found: " . scalar(@vmx_file_paths));
	return @vmx_file_paths;
}

#/////////////////////////////////////////////////////////////////////////////

=head2 get_vm_power_state

 Parameters  : $vmx_file_path
 Returns     : string
 Description : Returns a string containing the power state of the VM indicated
					by the vmx file path argument. The string returned may be one of
					the following values:
					on
					off
					suspended

=cut

sub get_vm_power_state {
	my $self = shift;
	if (ref($self) !~ /VCL::Module/i) {
		notify($ERRORS{'CRITICAL'}, 0, "subroutine was called as a function, it must be called as a class method");
		return;
	}
	
	# Get the vmx file path argument
	my $vmx_file_path = shift;
	if (!$vmx_file_path) {
		notify($ERRORS{'WARNING'}, 0, "vmx file path argument was not supplied");
		return;
	}
	my $vmx_file_name = $self->_get_file_name($vmx_file_path);
	
	# Run 'vmware-cmd <cfg> getstate'
	my $vmware_cmd_arguments = "\"$vmx_file_path\" getstate";
	my ($exit_status, $output) = $self->_run_vmware_cmd($vmware_cmd_arguments);
	return if !$output;
	
	# The output should look like this:
	# getstate() = off
	
	my $vm_power_state;
	if (grep(/=\s*on/i, @$output)) {
		$vm_power_state = 'on';
	}
	elsif (grep(/=\s*off/i, @$output)) {
		$vm_power_state = 'off';
	}
	elsif (grep(/=\s*suspended/i, @$output)) {
		$vm_power_state = 'suspended';
	}
	else {
		notify($ERRORS{'WARNING'}, 0, "unexpected output returned while attempting to determine power state of '$vmx_file_path', vmware-cmd arguments: '$vmware_cmd_arguments' output:\n" . join("\n", @$output));
		return;
	}
	
	notify($ERRORS{'DEBUG'}, 0, "power state of VM '$vmx_file_name': $vm_power_state");
	return $vm_power_state;
}

#/////////////////////////////////////////////////////////////////////////////

=head2 vm_power_on

 Parameters  : $vmx_file_path
 Returns     : boolean
 Description : Powers on the VM indicated by the vmx file path argument.

=cut

sub vm_power_on {
	my $self = shift;
	if (ref($self) !~ /VCL::Module/i) {
		notify($ERRORS{'CRITICAL'}, 0, "subroutine was called as a function, it must be called as a class method");
		return;
	}
	
	# Get the vmx file path argument
	my $vmx_file_path = shift;
	if (!$vmx_file_path) {
		notify($ERRORS{'WARNING'}, 0, "vmx file path argument was not supplied");
		return;
	}
	my $vmx_file_name = $self->_get_file_name($vmx_file_path);
	
	my $vmware_cmd_arguments = "\"$vmx_file_path\" start";
	my ($exit_status, $output) = $self->_run_vmware_cmd($vmware_cmd_arguments);
	return if !$output;
	
	# Expected output if the VM was not previously powered on:
	# start() = 1
	
	# Expected output if the VM was previously powered on:
	# VMControl error -8: Invalid operation for virtual machine's current state:
	# The requested operation ("start") could not be completed because it
	# conflicted with the state of the virtual machine ("on") at the time the
	# request was received. This error often occurs because the state of the
	# virtual machine changed before it received the request.
	
	# Expected output if the VM is not registered: /usr/bin/vmware-cmd: Could not
	# connect to VM /var/lib/vmware/Virtual Machines/Windows XP
	# Professional/Windows XP Professional.vmx
	#  (VMControl error -11: No such virtual machine: The config file
	#  /var/lib/vmware/Virtual Machines/Windows XP Professional/Windows XP
	#  Professional.vmx is not registered.
	# Please register the config file on the server. For example: vmware-cmd -s
	# register "/var/lib/vmware/Virtual Machines/Windows XP Professional/Windows
	# XP Professional.vmx")
	
	if (grep(/\(\"on\"\)/i, @$output)) {
		notify($ERRORS{'OK'}, 0, "VM is already powered on: '$vmx_file_name'");
		return 1;
	}
	elsif (grep(/=\s*1/i, @$output)) {
		notify($ERRORS{'OK'}, 0, "powered on VM: '$vmx_file_name'");
		return 1;
	}
	elsif (grep(/error -11/i, @$output)) {
		notify($ERRORS{'WARNING'}, 0, "unable to power on VM because it is not registered: '$vmx_file_path'");
		return;
	}
	else {
		notify($ERRORS{'WARNING'}, 0, "unexpected output returned while attempting to power on VM '$vmx_file_path', vmware-cmd arguments: '$vmware_cmd_arguments', output:\n" . join("\n", @$output));
		return;
	}
}

#/////////////////////////////////////////////////////////////////////////////

=head2 vm_power_off

 Parameters  : $vmx_file_path
 Returns     : boolean
 Description : Powers off the VM indicated by the vmx file path argument.

=cut

sub vm_power_off {
	my $self = shift;
	if (ref($self) !~ /VCL::Module/i) {
		notify($ERRORS{'CRITICAL'}, 0, "subroutine was called as a function, it must be called as a class method");
		return;
	}
	
	# Get the vmx file path argument
	my $vmx_file_path = shift;
	if (!$vmx_file_path) {
		notify($ERRORS{'WARNING'}, 0, "vmx file path argument was not supplied");
		return;
	}
	my $vmx_file_name = $self->_get_file_name($vmx_file_path);
	
	my $vmware_cmd_arguments = "\"$vmx_file_path\" stop hard";
	my ($exit_status, $output) = $self->_run_vmware_cmd($vmware_cmd_arguments);
	return if !$output;
	
	# Expected output if the VM was not previously powered on:
	# stop(hard) = 1
	
	# Expected output if the VM was previously powered on: VMControl error -8:
	# Invalid operation for virtual machine's current state: The requested
	# operation ("stop") could not be completed because it conflicted with the
	# state of the virtual machine ("off") at the time the request was received.
	# This error often occurs because the state of the virtual machine changed
	# before it received the request.
	
	# Expected output if the VM is not registered: /usr/bin/vmware-cmd: Could not
	# connect to VM /var/lib/vmware/Virtual Machines/Windows XP
	# Professional/Windows XP Professional.vmx
	#  (VMControl error -11: No such virtual machine: The config file
	#  /var/lib/vmware/Virtual Machines/Windows XP Professional/Windows XP
	#  Professional.vmx is not registered.
	# Please register the config file on the server. For example: vmware-cmd -s
	# register "/var/lib/vmware/Virtual Machines/Windows XP Professional/Windows
	# XP Professional.vmx")
	
	if (grep(/\(\"off\"\)/i, @$output)) {
		notify($ERRORS{'OK'}, 0, "VM is already powered off: '$vmx_file_name'");
		return 1;
	}
	elsif (grep(/=\s*1/i, @$output)) {
		notify($ERRORS{'OK'}, 0, "powered off VM: '$vmx_file_name'");
		return 1;
	}
	elsif (grep(/error -11/i, @$output)) {
		notify($ERRORS{'WARNING'}, 0, "unable to power off VM because it is not registered: '$vmx_file_path'");
		return;
	}
	else {
		notify($ERRORS{'WARNING'}, 0, "unexpected output returned while attempting to power off VM '$vmx_file_path', vmware-cmd arguments: '$vmware_cmd_arguments', output:\n" . join("\n", @$output));
		return;
	}
}

#/////////////////////////////////////////////////////////////////////////////

=head2 vm_register

 Parameters  : $vmx_file_path
 Returns     : boolean
 Description : Registers the VM indicated by the vmx file path argument.

=cut

sub vm_register {
	my $self = shift;
	if (ref($self) !~ /VCL::Module/i) {
		notify($ERRORS{'CRITICAL'}, 0, "subroutine was called as a function, it must be called as a class method");
		return;
	}
	
	# Get the vmx file path argument
	my $vmx_file_path = shift;
	if (!$vmx_file_path) {
		notify($ERRORS{'WARNING'}, 0, "vmx file path argument was not supplied");
		return;
	}
	my $vmx_file_name = $self->_get_file_name($vmx_file_path);
	
	my $vmware_cmd_arguments = "-s register \"$vmx_file_path\"";
	my ($exit_status, $output) = $self->_run_vmware_cmd($vmware_cmd_arguments);
	return if !$output;
	
	# Expected output if the VM is already registered:
	# VMControl error -20: Virtual machine already exists
	
	# Expected output if the VM is successfully registered:
	# register(<vmx path>) = 1
	
	if (grep(/error -20/i, @$output)) {
		notify($ERRORS{'OK'}, 0, "VM is already registered: '$vmx_file_name'");
		return 1;
	}
	elsif (grep(/=\s*1/i, @$output)) {
		notify($ERRORS{'OK'}, 0, "registered VM: '$vmx_file_name'");
		return 1;
	}
	else {
		notify($ERRORS{'WARNING'}, 0, "unexpected output returned while attempting to register VM '$vmx_file_path', vmware-cmd arguments: '$vmware_cmd_arguments', output:\n" . join("\n", @$output));
		return;
	}
}

#/////////////////////////////////////////////////////////////////////////////

=head2 vm_unregister

 Parameters  : $vmx_file_path
 Returns     : boolean
 Description : Unregisters the VM indicated by the vmx file path argument.

=cut

sub vm_unregister {
	my $self = shift;
	if (ref($self) !~ /VCL::Module/i) {
		notify($ERRORS{'CRITICAL'}, 0, "subroutine was called as a function, it must be called as a class method");
		return;
	}
	
	# Get the vmx file path argument
	my $vmx_file_path = shift;
	if (!$vmx_file_path) {
		notify($ERRORS{'WARNING'}, 0, "vmx file path argument was not supplied");
		return;
	}
	my $vmx_file_name = $self->_get_file_name($vmx_file_path);
	
	# Check if the VM is not registered
	if (!$self->is_vm_registered($vmx_file_path)) {
		notify($ERRORS{'OK'}, 0, "VM not unregistered because it is not registered: '$vmx_file_name'");
		return 1;
	}
	
	# Power off the VM if it is on
	my $vm_power_state = $self->get_vm_power_state($vmx_file_path) || '';
	if ($vm_power_state =~ /on/i && !$self->vm_power_off($vmx_file_path)) {
		notify($ERRORS{'WARNING'}, 0, "failed to power off VM before unregistering it: '$vmx_file_name', VM power state: $vm_power_state");
		return;
	}
	
	my $vmware_cmd_arguments = "-s unregister \"$vmx_file_path\"";
	my ($exit_status, $output) = $self->_run_vmware_cmd($vmware_cmd_arguments);
	return if !$output;
	
	# Expected output if the VM is not registered:
	# VMControl error -11: No such virtual machine
	
	# Expected output if the VM is successfully unregistered:
	# unregister(<vmx path>) = 1
	
	if (grep(/error -11/i, @$output)) {
		notify($ERRORS{'OK'}, 0, "VM is not registered: '$vmx_file_name'");
	}
	elsif (grep(/=\s*1/i, @$output)) {
		notify($ERRORS{'OK'}, 0, "unregistered VM: '$vmx_file_name'");
	}
	else {
		notify($ERRORS{'WARNING'}, 0, "unexpected output returned while attempting to unregister VM '$vmx_file_path', vmware-cmd arguments: '$vmware_cmd_arguments', output:\n" . join("\n", @$output));
		return;
	}
	
	# Make sure the VM is not registered
	if ($self->is_vm_registered($vmx_file_path)) {
		notify($ERRORS{'WARNING'}, 0, "failed to unregister VM, it appears to still be registered: '$vmx_file_path'");
		return;
	}
	
	return 1;
}

#/////////////////////////////////////////////////////////////////////////////

=head2 get_virtual_disk_controller_type

 Parameters  : $vmdk_file_path
 Returns     : 
 Description : Retrieves the disk controller type configured for the virtual
					disk specified by the vmdk file path argument. A string is
					returned containing one of the following values:
               -ide
					-buslogic
					-lsilogic

=cut

sub get_virtual_disk_controller_type {
	my $self = shift;
	if (ref($self) !~ /VCL::Module/i) {
		notify($ERRORS{'CRITICAL'}, 0, "subroutine was called as a function, it must be called as a class method");
		return;
	}
	
	# Get the vmdk file path argument
	my $vmdk_file_path = shift;
	if (!$vmdk_file_path) {
		notify($ERRORS{'WARNING'}, 0, "vmdk file path argument was not supplied");
		return;
	}
	my $vmdk_file_name = $self->_get_file_name($vmdk_file_path);
	
	my $vmhost_computer_name = $self->vmhost_os->data->get_computer_short_name();
	
	my $command = "grep -i adapterType \"$vmdk_file_path\"";
	my ($exit_status, $output) = $self->vmhost_os->execute($command);
	if (!defined($output)) {
		notify($ERRORS{'WARNING'}, 0, "failed to run command on VM host $vmhost_computer_name: '$command'");
	}
	
	my ($adapter_type) = "@$output" =~ /adapterType\s*=\s*\"(\w+)\"/i;
	
	if ($adapter_type) {
		notify($ERRORS{'DEBUG'}, 0, "adapter type configured in '$vmdk_file_name': $adapter_type");
		return $adapter_type;
	}
	else {
		notify($ERRORS{'WARNING'}, 0, "unable to determine adapter type configured in '$vmdk_file_name', command: '$command', output:\n" . join("\n", @$output));
		return;
	}
}

#/////////////////////////////////////////////////////////////////////////////

=head2 get_virtual_disk_type

 Parameters  : $vmdk_file_path
 Returns     : 
 Description : Retrieves the disk type configured for the virtual
					disk specified by the vmdk file path argument. A string is
					returned containing one of the following values:
               -monolithicSparse
					-twoGbMaxExtentSparse
					-monolithicFlat
					-twoGbMaxExtentFlat

=cut

sub get_virtual_disk_type {
	my $self = shift;
	if (ref($self) !~ /VCL::Module/i) {
		notify($ERRORS{'CRITICAL'}, 0, "subroutine was called as a function, it must be called as a class method");
		return;
	}
	
	# Get the vmdk file path argument
	my $vmdk_file_path = shift;
	if (!$vmdk_file_path) {
		notify($ERRORS{'WARNING'}, 0, "vmdk file path argument was not supplied");
		return;
	}
	my $vmdk_file_name = $self->_get_file_name($vmdk_file_path);
	
	my $vmhost_computer_name = $self->vmhost_os->data->get_computer_short_name();
	
	my $command = "grep -i createType \"$vmdk_file_path\"";
	my ($exit_status, $output) = $self->vmhost_os->execute($command);
	if (!defined($output)) {
		notify($ERRORS{'WARNING'}, 0, "failed to run command on VM host $vmhost_computer_name: '$command'");
	}
	
	my ($disk_type) = "@$output" =~ /createType\s*=\s*\"(\w+)\"/i;
	
	if ($disk_type) {
		notify($ERRORS{'DEBUG'}, 0, "disk type configured in '$vmdk_file_name': $disk_type");
		return $disk_type;
	}
	else {
		notify($ERRORS{'WARNING'}, 0, "unable to determine disk type configured in '$vmdk_file_name', command: '$command', output:\n" . join("\n", @$output));
		return;
	}
}


#/////////////////////////////////////////////////////////////////////////////

=head2 get_virtual_disk_hardware_version

 Parameters  : $vmdk_file_path
 Returns     : integer
 Description : Retrieves the hardware version configured for the virtual
					disk specified by the vmdk file path argument. False is returned
					if the hardware version cannot be retrieved.

=cut

sub get_virtual_disk_hardware_version {
	my $self = shift;
	if (ref($self) !~ /VCL::Module/i) {
		notify($ERRORS{'CRITICAL'}, 0, "subroutine was called as a function, it must be called as a class method");
		return;
	}
	
	# Get the vmdk file path argument
	my $vmdk_file_path = shift;
	if (!$vmdk_file_path) {
		notify($ERRORS{'WARNING'}, 0, "vmdk file path argument was not supplied");
		return;
	}
	my $vmdk_file_name = $self->_get_file_name($vmdk_file_path);
	
	my $vmhost_computer_name = $self->vmhost_os->data->get_computer_short_name();
	
	my $command = "grep -i virtualHWVersion \"$vmdk_file_path\"";
	my ($exit_status, $output) = $self->vmhost_os->execute($command);
	if (!defined($output)) {
		notify($ERRORS{'WARNING'}, 0, "failed to run command on VM host $vmhost_computer_name: '$command'");
	}
	
	my ($hardware_version) = "@$output" =~ /virtualHWVersion\s*=\s*\"(\w+)\"/i;
	
	if (defined($hardware_version)) {
		notify($ERRORS{'DEBUG'}, 0, "hardware version configured in '$vmdk_file_name': $hardware_version");
		return $hardware_version;
	}
	else {
		notify($ERRORS{'WARNING'}, 0, "unable to determine hardware version configured in '$vmdk_file_name', command: '$command', output:\n" . join("\n", @$output));
		return;
	}
}

#/////////////////////////////////////////////////////////////////////////////

1;
__END__

=head1 SEE ALSO

L<http://cwiki.apache.org/VCL/>

=cut