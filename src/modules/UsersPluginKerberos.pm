#! /usr/bin/perl -w
# ------------------------------------------------------------------------------
# Copyright (c) 2014 SUSE LINUX Products All Rights Reserved.
#
#
# This program is free software; you can redistribute it and/or modify it under
# the terms of version 2 of the GNU General Public License as published by the
# Free Software Foundation.
#
# This program is distributed in the hope that it will be useful, but WITHOUT
# ANY WARRANTY; without even the implied warranty of MERCHANTABILITY or FITNESS
# FOR A PARTICULAR PURPOSE.  See the GNU General Public License for more details.
#
# You should have received a copy of the GNU General Public License along with
# this program; if not, contact Novell, Inc.
#
# To contact Novell about this file by physical or electronic mail, you may find
# current contact information at www.novell.com.
# ------------------------------------------------------------------------------
#

#
# This is the API part of UsersPluginKerberos plugin:
# Creates the Kerberos principials
#
# For documentation and examples of function arguments and return values, see
# UsersPluginLDAPAll.pm

package UsersPluginKerberos;

use strict;

use YaST::YCP qw(:LOGGING sformat);
use YaPI;
use Data::Dumper;

textdomain("users");

our %TYPEINFO;

##--------------------------------------
##--------------------- global imports

YaST::YCP::Import ("SCR");

##--------------------------------------
##--------------------- global variables

# error message, returned when some plugin function fails
my $error	= "";

# internal name
my $name	= "UsersPluginKerberos";

##----------------------------------------
##--------------------- internal functions

# internal function:
# check if given key (second parameter) is contained in a list (1st parameter)
# if 3rd parameter is true (>0), ignore case
sub contains {
    my ($list, $key, $ignorecase) = @_;
    if (!defined $list || ref ($list) ne "ARRAY" || @{$list} == 0) {
	return 0;
    }
    if ($ignorecase) {
        if ( grep /^\Q$key\E$/i, @{$list} ) {
            return 1;
        }
    } else {
        if ( grep /^\Q$key\E$/, @{$list} ) {
            return 1;
        }
    }
    return 0;
}

##------------------------------------------
##--------------------- global API functions

# All functions have 2 "any" parameters: these mean:
# 1st: configuration map (hash) - e.g. saying if we work with user or group
# 2nd: data map (hash) of user/group to work with
# for details, see UsersPluginLDAPAll.pm

# Return the names of provided functions
BEGIN { $TYPEINFO{Interface} = ["function", ["list", "string"], "any", "any"];}
sub Interface {

    my $self		= shift;
    my @interface 	= (
	    "Name",
	    "Summary",
	    "Restriction",
	    "Write",
	    "Add",
	    "AddBefore",
	    "Edit",
	    "EditBefore",
	    "Interface",
	    "PluginPresent",
	    "PluginRemovable",
	    "Error",
    );
    return \@interface;
}

# return error message, generated by plugin
BEGIN { $TYPEINFO{Error} = ["function", "string", "any", "any"];}
sub Error {

    return $error;
}


# return plugin name, used for GUI (translated)
BEGIN { $TYPEINFO{Name} = ["function", "string", "any", "any"];}
sub Name {

    # plugin name
    return __("Kerberos Configuration");
}

##------------------------------------
# Return plugin summary (to be shown in table with all plugins)
BEGIN { $TYPEINFO{Summary} = ["function", "string", "any", "any"];}
sub Summary {

    my ($self, $config, $data)  = @_;

    # user plugin summary (table item)
    return __("No Kerberos Management for Groups") if ($config->{"what"} eq "group");

    # user plugin summary (table item)
    return __("Manage Kerberos Principials");
}

##------------------------------------
# Checks the current data map of user/group (2nd parameter) and returns
# true if given user/group has this plugin enabled
BEGIN { $TYPEINFO{PluginPresent} = ["function", "boolean", "any", "any"];}
sub PluginPresent {
    my ($self, $config, $data)  = @_;

    if ($config->{"what"} eq "group") {
	y2debug ("Kerberos plugin not present");
	return 0;
    }
    my $out	= SCR->Execute (".target.bash_output", '/usr/lib/mit/sbin/kadmin.local -nq "list_principals '.$data->{uid}.'*" | grep '.$data->{uid}.'*');
    if ($out->{"stdout"} =~ /^$data->{uid}/ ) {
	y2milestone ("Kerberos plugin present");
	return 1;
    } else {
	y2milestone ("Kerberos plugin not present");
	return 0;
    }
}

##------------------------------------
# Is it possible to remove this plugin from user/group: setting all quota
# values to 0.
BEGIN { $TYPEINFO{PluginRemovable} = ["function", "boolean", "any", "any"];}
sub PluginRemovable {

    return YaST::YCP::Boolean (0);
}


##------------------------------------
# Type of objects this plugin is restricted to.
# Plugin is restricted to local users
BEGIN { $TYPEINFO{Restriction} = ["function",
    ["map", "string", "any"], "any", "any"];}
sub Restriction {

    return {
	    "ldap"	=> 1,
	    "group"	=> 0,
	    "user"	=> 1
    };
}


# this will be called at the beggining of Users::AddUser/AddGroup
# Check if it is possible to add this plugin here.
# (Could be called multiple times for one user/group)
BEGIN { $TYPEINFO{AddBefore} = ["function",
    ["map", "string", "any"],
    "any", "any"];
}
sub AddBefore {

    my ($self, $config, $data)  = @_;

    return $data;
}

# This will be called at the end of Users::Add* : modify the object map
# with quota data
BEGIN { $TYPEINFO{Add} = ["function", ["map", "string", "any"], "any", "any"];}
sub Add {

    my ($self, $config, $data)  = @_;
    y2debug ("Add Kerveros called");
    return $data;
}

# This will be called at the beggining of Users::EditUser/EditGroup
# Check if it is possible to add this plugin here.
# (Could be called multiple times for one user/group)
BEGIN { $TYPEINFO{EditBefore} = ["function",
    ["map", "string", "any"],
    "any", "any"];
}
sub EditBefore {

    my ($self, $config, $data)  = @_;

    return $data;
}

# This will be called at the end of Users::Edit* : modify the object map
# with quota data
BEGIN { $TYPEINFO{Edit} = ["function",
    ["map", "string", "any"],
    "any", "any"];
}
sub Edit {
    my ($self, $config, $data)  = @_;
    y2debug ("Edit Kerberos called");
    return $data;
}

# What should be done after user is finally written (this is called only once)
BEGIN { $TYPEINFO{Write} = ["function", "boolean", "any", "any"];}
sub Write {

    my ($self, $config, $data)  = @_;

#y2milestone(Dumper($data));
    if( $data->{what} eq 'add_user' ) {
       my $out = SCR->Execute (".target.bash_output", '/usr/lib/mit/sbin/kadmin.local -q "addprinc -pw '.$data->{text_userpassword}.' '.$data->{uid}.'"');
    }
    elsif( $data->{what} eq 'del_user' ) {
       my $out  = SCR->Execute (".target.bash_output", '/usr/lib/mit/sbin/kadmin.local -q "delprinc '.$data->{uid}.'"');
    }
    elsif( $data->{what} eq 'edit_user' ) {
     if( defined $data->{text_userpassword} ) {
       my $out  = SCR->Execute (".target.bash_output", '/usr/lib/mit/sbin/kadmin.local -q "change_password -pw '.$data->{text_userpassword}.' '.$data->{uid}.'"');
     }
    }
    return YaST::YCP::Boolean (1);
}
42
# EOF
