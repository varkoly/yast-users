#! /usr/bin/perl -w
#
# UsersCache module written in Perl
#

package UsersCache;

use strict;

use ycp;
use YaST::YCP qw(Term);

use Locale::gettext;
use POSIX;     # Needed for setlocale()

setlocale(LC_MESSAGES, "");
textdomain("users");

our %TYPEINFO;

my $user_type		= "local";
my $group_type		= "local";

my %usernames		= (); #TODO used by phone-services, mail, inetd...
my %homes		= ();
my %uids		= ();
my %user_items		= ();
my %userdns		= ();

my %groupnames		= ();
my %gids		= ();
my %group_items		= ();

my %removed_uids	= ();
my %removed_usernames	= ();

my %min_uid			= (
    "local"		=> 1000,
    "system"		=> 100,
    "ldap"		=> 1000
);

my %min_gid			= (
    "local"		=> 1000,
    "system"		=> 100,
    "ldap"		=> 1000
);

my %max_uid			= (
    "local"		=> 60000,
    "system"		=> 499,
    "ldap"		=> 60000
);

my %max_gid			= (
    "local"		=> 60000,
    "system"		=> 499,
    "ldap"		=> 60000
);

# the highest ID in use
my %last_uid		= (
    "local"		=> 1000,
    "system"		=> 100,
);

my %last_gid		= (
    "local"		=> 1000,
    "system"		=> 100,
);

our $max_length_login 	= 32; # reason: see for example man utmp, UT_NAMESIZE
our $min_length_login 	= 2;

our $max_length_groupname 	= 8; # TODO:why only 8?
our $min_length_groupname	= 2;

# UI-related (summary table) variables:
my $focusline_user;
my $focusline_group;
my $current_summary	= "users";

# usernames generated by "Propose" button
my @proposed_usernames	= ();
# number of clicks of "Propose" (-1 means: generate new list)
my $proposal_count	= -1;

# list of references to list of current user items
my @current_user_items	= ();
my @current_group_items	= ();

# which sets of users are we working with:
my @current_users	= ();
my @current_groups	= ();

# Is the currrent table view "customized"?
my $customized_usersview	= 1;
my $customized_groupsview	= 1;

# the final answer ;-)
my $the_answer			= 42;

##------------------------------------
##------------------- global imports

YaST::YCP::Import ("Mode");
YaST::YCP::Import ("SCR");
YaST::YCP::Import ("Security");
YaST::YCP::Import ("Progress");

##-------------------------------------------------------------------------
##----------------- various routines --------------------------------------

BEGIN { $TYPEINFO{ResetProposing} = ["function", "void"]; }
sub ResetProposing {
    $proposal_count	= -1;
}


BEGIN { $TYPEINFO{ProposeUsername} = ["function", "string", "string"]; }
sub ProposeUsername {

    my $cn		= $_[0];
    my $default_login  	= "lxuser";

    if ($proposal_count == -1) {
	# generate new list of possible usernames each time cn is changed

	@proposed_usernames	= ();
	# do not propose username with uppercase (problematic: bug #26409)
	my @parts 		= split (/ /, lc ($cn));
	my %tested_usernames 	= ();

	# 1st: add some interesting modifications...
	my $i = 0;
	foreach my $part (@parts) { #TODO use 'map'
	    $tested_usernames{$part}	= 1;
	}
	while ($i < @parts - 1) {
	    my $j = $i;
	    while ($j < @parts - 1) {
		$tested_usernames{$parts[$i].$parts[$j+1]}	= 1;
		$tested_usernames{$parts[$j+1].$parts[$i]}	= 1;
		$tested_usernames{substr ($parts[$i], 0, 1).$parts[$j+1]} = 1;
		$tested_usernames{$parts[$j+1].substr ($parts[$i], 0, 1)} = 1;
		$j++;
	    }
	    $i++;
	}
	$tested_usernames{$default_login}	= 1;

	# 2nd: check existence
	foreach my $name (sort keys %tested_usernames) {
	    my $name_count = 0;
	    while (UsernameExists ($name)) {
		$name .= "$name_count";
		$name_count ++;
	    }
	    if (length ($name) < $min_length_login ||
		length ($name) > $max_length_login) {
		next;
	    }
	    push @proposed_usernames, $name;
	};

	if (!UsernameExists ("$the_answer") && @proposed_usernames > 11) {
	    push @proposed_usernames, "$the_answer";
	}
	$proposal_count = 0;
    }
    if ($proposal_count >= @proposed_usernames) {
	$proposal_count = 0;
    }

    my $login = $proposed_usernames[$proposal_count] || $default_login;

    $proposal_count ++;

    return $login;
}

sub DebugMap {

    my %map = %{$_[0]};
    
    y2internal ("--------------------------- start of output");
    foreach my $key (sort keys %map) {
    	if (ref ($map{$key}) eq "ARRAY") {
	    y2warning ("$key ---> (list)\n", join ("\n", sort @{$map{$key}}));
	}
	else {
	    y2warning ("$key ---> ", $map{$key});
	}
    }
    y2internal ("--------------------------- end of output");
}

##-------------------------------------------------------------------------
##----------------- current users (group) routines, customization r. ------

BEGIN { $TYPEINFO{SetCurrentUsers} = ["function", "void", ["list", "string"]];}
sub SetCurrentUsers {

    @current_users	= @{$_[0]}; # e.g. ("local", "system")

    @current_user_items = ();
    foreach my $type (@current_users) {
	push @current_user_items, $user_items{$type};
	# e.g. ( pointer to "local items", pointer to "system items")
    };
}

##------------------------------------
BEGIN { $TYPEINFO{SetCustomizedUsersView} = ["function", "void", "boolean"];}
sub SetCustomizedUsersView {
    $customized_usersview = $_[0];
}

##------------------------------------
BEGIN { $TYPEINFO{CustomizedUsersView} = ["function", "boolean"];}
sub CustomizedUsersView {
    return $customized_usersview;
}


##------------------------------------
BEGIN { $TYPEINFO{SetCurrentGroups} = ["function", "void", ["list", "string"]];}
sub SetCurrentGroups {

    @current_groups	= @{$_[0]}; # e.g. ("local", "system")

    @current_group_items = ();
    foreach my $type (@current_groups) {
	push @current_group_items, $group_items{$type};
	# e.g. ( pointer to "local items", pointer to "system items")
    };
}

##------------------------------------
BEGIN { $TYPEINFO{SetCustomizedGroupsView} = ["function", "void", "boolean"];}
sub SetCustomizedGroupsView {
    $customized_groupsview = $_[0];
}

##------------------------------------
BEGIN { $TYPEINFO{CustomizedGroupsView} = ["function", "boolean"];}
sub CustomizedGroupsView {
    return $customized_groupsview;
}

##-------------------------------------------------------------------------
##----------------- test routines -----------------------------------------


##------------------------------------
sub UIDConflicts {

    my $ret = SCR::Read (".uid.uid", $_[0]);
    return !$ret;
}
 
##------------------------------------
BEGIN { $TYPEINFO{UIDExists} = ["function", "boolean", "integer"]; }
sub UIDExists {

    my $ret	= 0;
    my $uid	= $_[0];

    foreach my $type (keys %uids) {
	if (defined $uids{$type}{$uid}) { $ret = 1; }
    };
    # for autoyast, check only loaded sets
    if ($ret || Mode::config () || Mode::test ()) {
	return $ret;
    }
    # not found -> check all sets via agent...
    $ret = UIDConflicts ($uid);
    if ($ret) {
	# check if uid wasn't just deleted...
	my @sets_to_check = ("local", "system");
	# LDAP: do not allow change uid of one user and use old one by
	# another user - because users are saved by calling extern tool
	# and colisions can be hardly avoided
	if ($user_type ne "ldap") {
	    push @sets_to_check, "ldap";
	}
	foreach my $type (@sets_to_check) {
	    if (defined $removed_uids{$type}{$uid}) { $ret = 0; }
	};
    }
    return $ret;
}

sub UsernameConflicts {

    my $ret = SCR::Read (".uid.username", $_[0]);
    return !$ret;
}

##------------------------------------
BEGIN { $TYPEINFO{UsernameExists} = ["function", "boolean", "string"]; }
sub UsernameExists {

    my $ret		= 0;
    my $username	= $_[0];

    foreach my $type (keys %usernames) {
	if (defined $usernames{$type}{$username}) { $ret = 1; }
    };
    if ($ret || Mode::config () || Mode::test ()) {
	return $ret;
    }
    $ret = UsernameConflicts ($username);
    if ($ret) {
	my @sets_to_check = ("local", "system");
	if ($user_type ne "ldap") {
	    push @sets_to_check, "ldap";
	}
	foreach my $type (@sets_to_check) {
	    if (defined $removed_usernames{$type}{$username}) {
		$ret = 0;
	    }
	};
    }
    return $ret;
}


##------------------------------------
BEGIN { $TYPEINFO{GIDExists} = ["function", "boolean", "integer"]; }
sub GIDExists {

    my $ret	= 0;
    my $gid	= $_[0];
    
    if ($group_type eq "ldap") {
	$ret = defined $gids{$group_type}{$gid};
    }
    else {
	$ret = (defined $gids{"local"}{$gid} &&
		defined $gids{"system"}{$gid});
    }
    return $ret;
}

##------------------------------------
BEGIN { $TYPEINFO{GroupnameExists} = ["function", "boolean", "string"]; }
sub GroupnameExists {

    my $ret		= 0;
    my $groupname	= $_[0];
    
    if ($group_type eq "ldap") {
	$ret = defined $groupnames{$group_type};
    }
    else {
	$ret = (defined $groupnames{"local"}{$groupname} &&
		defined $groupnames{"system"}{$groupname});
    }
    return $ret;
}

##------------------------------------
# Check if homedir is not owned by another user
# Doesn't check directory existence, only looks to set of used directories
# @param home the name
# @return true if directory is used as another user's home directory
BEGIN { $TYPEINFO{HomeExists} = ["function", "boolean", "string"]; }
sub HomeExists {

    my $home		= $_[0];
    my $ret		= 0;
    my @sets_to_check	= ("local", "system");

#    if (ldap_file_server) { FIXME
#	sets_to_check = add (sets_to_check, "ldap");
#    }
#    else if (user_type == "ldap") //ldap, client only
#    {
#	sets_to_check = ["ldap"];
#    }

    foreach my $type (@sets_to_check) {
        if (defined $homes{$type}{$home}) {
	    $ret = 1;
	}
    };
    return $ret;
}

##-------------------------------------------------------------------------
##----------------- get routines ------------------------------------------

#------------------------------------
BEGIN { $TYPEINFO{GetCurrentFocus} = ["function", "integer"]; }
sub GetCurrentFocus {

    if ($current_summary eq "users") {
	return $focusline_user;
    }
    else {
	return $focusline_group;
    }
}

#------------------------------------
BEGIN { $TYPEINFO{SetCurrentFocus} = ["function", "void", "integer"]; }
sub SetCurrentFocus {

    if ($current_summary eq "users") {
	$focusline_user = $_[0];
    }
    else {
	$focusline_group = $_[0];
    }
}


#------------------------------------
BEGIN { $TYPEINFO{GetCurrentSummary} = ["function", "string"]; }
sub GetCurrentSummary {
    return $current_summary;
}

#------------------------------------
BEGIN { $TYPEINFO{SetCurrentSummary} = ["function", "void", "string"]; }
sub SetCurrentSummary {
    $current_summary = $_[0];
}

#------------------------------------
BEGIN { $TYPEINFO{ChangeCurrentSummary} = ["function", "void"]; }
sub ChangeCurrentSummary {
    
    if ($current_summary eq "users") {
	$current_summary = "groups";
    }
    else {
	$current_summary = "users";
    }
}


#------------------------------------ for User Details...
BEGIN { $TYPEINFO{GetAllGroupnames} = ["function",
    ["map", "string", ["map", "string", "integer"]] ];
}
sub GetAllGroupnames {

    return \%groupnames;
}

##------------------------------------
BEGIN { $TYPEINFO{GetGroupnames} = ["function", ["list", "string"], "string"];}
sub GetGroupnames {

    return keys %{$groupnames{$_[0]}};
}


##------------------------------------
BEGIN { $TYPEINFO{GetUsernames} = ["function", ["list", "string"], "string"];}
sub GetUsernames {

    return keys %{$usernames{$_[0]}};
}

##------------------------------------
BEGIN { $TYPEINFO{GetUserItems} = ["function", ["list", "term"]];}
sub GetUserItems {

# @current_user_items: ( pointer to local hash, pointer to system hash, ...)

    my @items;
    foreach my $itemref (@current_user_items) {
	foreach my $id (sort keys %{$itemref}) {
	    push @items, $itemref->{$id};
	}
    }
    return @items;
}

##------------------------------------
BEGIN { $TYPEINFO{GetGroupItems} = ["function", ["list", "term"]];}
sub GetGroupItems {

    my @items;
    foreach my $itemref (@current_group_items) {
	foreach my $id (sort keys %{$itemref}) {
	    push @items, $itemref->{$id};
	}
    }
    return @items;
}

##------------------------------------
BEGIN { $TYPEINFO{GetUserType} = ["function", "string"]; }
sub GetUserType {

    return $user_type;
}

##------------------------------------
BEGIN { $TYPEINFO{GetGroupType} = ["function", "string"]; }
sub GetGroupType {

    return $group_type;
}

##------------------------------------
BEGIN { $TYPEINFO{GetMinUID} = ["function",
    "integer",
    "string"]; #user type
}
sub GetMinUID {

    if (defined $min_uid{$_[0]}) {
	return $min_uid{$_[0]};
    }
    return 0;
}

##------------------------------------
BEGIN { $TYPEINFO{GetMaxUID} = ["function",
    "integer",
    "string"]; #user type
}
sub GetMaxUID {

    if (defined $max_uid{$_[0]}) {
	return $max_uid{$_[0]};
    }
    return 60000;
}


##------------------------------------
BEGIN { $TYPEINFO{NextFreeUID} = ["function", "integer"]; }
sub NextFreeUID {

    my $ret;
    my $max	= GetMaxUID ($user_type);
    my $uid	= $last_uid{$user_type};

    do {
        if (UIDExists ($uid)) {
            $uid++;
	}
        else {
            $last_uid{$user_type} = $uid;
            return $uid;
        }
    } until ( $uid == $max );
    return $ret;
}

##------------------------------------
BEGIN { $TYPEINFO{GetMinGID} = ["function",
    "integer",
    "string"];
}
sub GetMinGID {

    if (defined $min_gid{$_[0]}) {
	return $min_gid{$_[0]};
    }
    return 0;
}
##------------------------------------
BEGIN { $TYPEINFO{GetMaxGID} = ["function",
    "integer",
    "string"];
}
sub GetMaxGID {

    if (defined $max_gid{$_[0]}) {
	return $max_gid{$_[0]};
    }
    return 60000;
}


##------------------------------------
BEGIN { $TYPEINFO{NextFreeGID} = ["function", "integer"]; }
sub NextFreeGID {

    my $ret;
    my $max	= GetMaxGID ($group_type);
    my $gid	= 500;
    do {
        if (GIDExists ($gid)) {
            $gid++;
	}
        else {
            $last_gid{$group_type} = $gid;
            return $gid;
        }
    } until ( $gid == $max );
    return $ret;
}


##-------------------------------------------------------------------------
##----------------- data manipulation routines ----------------------------

##------------------------------------
BEGIN { $TYPEINFO{SetUserType} = ["function", "void", "string"]; }
sub SetUserType {

    $user_type = $_[0];
}

##------------------------------------
BEGIN { $TYPEINFO{SetGroupType} = ["function", "void", "string"]; }
sub SetGroupType {

    $group_type = $_[0];
}


##------------------------------------
# build item for one user
sub BuildUserItem {
    
    my %user		= %{$_[0]};
    my $uid		= $user{"uidNumber"};
    my $username	= $user{"username"} || "";
    my $full		= $user{"cn"} || "";

#    if ($user{"type"} eq "system") {
#	$full		= SystemUsers (full); FIXME translated names!
#    }

    my $groupname	= $user{"groupname"} || "";
    my %grouplist	= %{$user{"grouplist"}};

    if ($groupname ne "") {
    	$grouplist{$groupname}	= 1;
    }
    my $all_groups	= join (",", keys %grouplist);

    my $id = YaST::YCP::Term ("id", $uid);
    my $t = YaST::YCP::Term ("item", $id, $username, $full, $uid, $all_groups);

    return $t;
}

BEGIN { $TYPEINFO{BuildUserItemList} = ["function",
    "void",
    "string",
    ["map", "integer", [ "map", "string", "any"]] ];
}
sub BuildUserItemList {

    if (Mode::test ()) { return; }

    my $type		= $_[0];
    my %map_of_users	= %{$_[1]};
    $user_items{$type}	= {};

    foreach my $uid (keys %map_of_users) {
        $user_items{$type}{$uid}	= BuildUserItem ($map_of_users{$uid});
    };
}


##------------------------------------
# build item for one group
sub BuildGroupItem {

    my %group		= %{$_[0]};
    my $gid		= $group{"gidNumber"};
    my $groupname	= $group{"groupname"} || "";

    my %userlist	= ();
    if (defined ($group{"userlist"})) {
	%userlist 	= %{$group{"userlist"}};
    }
    my %more_users	= ();
    if (defined ($group{"more_users"})) {
	%more_users	= %{$group{"more_users"}};
    }
    if ($group{"type"} eq "ldap") {
	%userlist	= %{$group{"uniqueMember"}};
	# TODO there are DN's, not usernames...
    }

    my @all_users	= ();
    my @userlist	= keys %userlist;
    my $i		= 0;

    while ($i < $the_answer && defined $userlist[$i]) {

	push @all_users, $userlist[$i];
	$i++;
    }
    
    my $count		= @all_users;
    my @more_users	= keys %more_users;
    my $j		= 0;

    while ($count + $j < $the_answer && defined $more_users[$j]) {

	push @all_users, $more_users[$j];
	$j++;
    }
    if (defined $more_users[$j] || defined $userlist[$i]) {
	push @all_users, "...";
    }

    my $all_users	= join (",", @all_users);

    my $id = YaST::YCP::Term ("id", $gid);
    my $t = YaST::YCP::Term ("item", $id, $groupname, $gid, $all_users);

    return $t;
}

##------------------------------------
BEGIN { $TYPEINFO{BuildGroupItemList} = ["function",
    "void",
    "string",
    ["map", "integer", [ "map", "string", "any"]] ];
}
sub BuildGroupItemList {

    if (Mode::test ()) { return; }

    my $type		= $_[0];
    my %map_of_groups	= %{$_[1]};
    $group_items{$type}	= {};

    foreach my $uid (keys %map_of_groups) {
        $group_items{$type}{$uid}	= BuildGroupItem ($map_of_groups{$uid});
    };
}


##------------------------------------
# Update the cache after changing user
# @param user the user's map
BEGIN { $TYPEINFO{CommitUser} = ["function",
    "void",
    ["map", "string", "any" ]];
}
sub CommitUser {

    my %user		= %{$_[0]};
    my $what		= $user{"what"};
    my $type		= $user{"type"};
    my $org_type	= $user{"org_type"} || $type;
    my $uid		= $user{"uidNumber"};
    my $org_uid		= $user{"org_uidNumber"} || $uid;
    my $home		= $user{"homeDirectory"};
    my $org_home	= $user{"org_homeDirectory"} || $home;
    my $username	= $user{"username"};
    my $org_username	= $user{"org_username"} || $username;

    my $dn		= $user{"dn"} || $username;
    my $org_dn		= $user{"org_dn"} || $dn;


    if ($what eq "add_user") {
	if ($type eq "ldap") {
	    $userdns{$dn}	= 1;
	}
	if (defined $removed_uids{$type}{$uid}) {
	    delete $removed_uids{$type}{$uid};
	}
        $uids{$type}{$uid}		= 1;
        $homes{$type}{$home}		= 1;
        $usernames{$type}{$username}	= 1;
	if (defined $removed_usernames{$type}{$username}) {
	    delete $removed_usernames{$type}{$username};
	}
	$user_items{$type}{$uid}	= BuildUserItem (\%user);

	$focusline_user = $uid;
    }
    elsif ($what eq "edit_user" || $what eq "group_change") {
        if ($uid != $org_uid) {
            delete $uids{$org_type}{$org_uid};
            $uids{$type}{$uid}				= 1;
	    if (defined $removed_uids{$type}{$uid}) {
		delete $removed_uids{$type}{$uid};
	    }
	    $removed_uids{$org_type}{$org_uid}		= 1;
	}
        if ($home ne $org_home || $type ne $org_type) {
            delete $homes{$org_type}{$org_home};
            $homes{$type}{$home}	= 1;
        }
        if ($username ne $org_username || $type ne $org_type) {
            delete $usernames{$org_type}{$org_username};
            $usernames{$type}{$username}			= 1;
	    if (defined $removed_usernames{$type}{$username}) {
		delete $removed_usernames{$type}{$username};
	    }
	    $removed_usernames{$org_type}{$org_username}	= 1;
	    if ($type eq "ldap") {
		delete $userdns{$org_dn};
		$userdns{$dn}	= 1;
	    }
        }
        delete $user_items{$org_type}{$org_uid};
        $user_items{$type}{$uid}	= BuildUserItem (\%user);

	if ($what ne "group_change") {
	    $focusline_user = $uid;
	}
	if ($org_type ne $type)
	{
	    undef $focusline_user;
	}
    }
    elsif ($what eq "delete_user") {
	if ($type eq "ldap") {
		delete $userdns{$org_dn};
	}
        delete $uids{$type}{$uid};
        delete $homes{$type}{$home};
        delete $usernames{$type}{$username};
	delete $user_items{$type}{$uid};

	$removed_uids{$type}{$uid}		= 1;
	$removed_usernames{$type}{$username}	= 1;

	undef $focusline_user;
    }
}

##------------------------------------
# Update the cache after changing group
# @param group the group's map
BEGIN { $TYPEINFO{CommitGroup} = ["function",
    "void",
    ["map", "string", "any" ]];
}
sub CommitGroup {

    my %group		= %{$_[0]};
    my $what		= $group{"what"};
    my $type		= $group{"type"};

    my $org_type	= $group{"org_type"} || $type;
    my $groupname	= $group{"groupname"};
    my $org_groupname	= $group{"org_groupname"} || $groupname;
    my $gid		= $group{"gidNumber"};
    my $org_gid		= $group{"org_gidNumber"} || $gid;

    if ($what eq "add_group") {
        $gids{$type}{$gid}		= 1;
        $groupnames{$type}{$groupname}	= 1;
	$group_items{$type}{$gid}	= BuildGroupItem (\%group);
	$focusline_group = $gid;
    }
    if ($what eq "edit_group") {
        if ($gid != $org_gid) {
            delete $gids{$org_type}{$org_gid};
            $gids{$type}{$gid}				= 1;
        }
        if ($groupname ne $org_groupname || $type ne $org_type) {
            delete $groupnames{$org_type}{$org_groupname};
            $groupnames{$type}{$groupname}			= 1;
        }
	$focusline_group = $gid;
    }
    if ($what eq "edit_group" || $what eq "user_change" ||
        $what eq "user_change_default") {

	delete $group_items{$org_type}{$org_gid};
	$group_items{$type}{$gid}	= BuildGroupItem (\%group);
	if ($org_type ne $type) {
	    undef $focusline_group;
	}
    }
    if ($what eq "delete_group") {
        delete $gids{$org_type}{$org_gid};
        delete $groupnames{$org_type}{$org_groupname};
	delete $group_items{$org_type}{$org_gid};
	undef $focusline_group;
    }
}


##-------------------------------------------------------------------------
##----------------- read routines -----------------------------------------
    
##------------------------------------
# initialize constants with the values from Security module
BEGIN { $TYPEINFO{InitConstants} = ["function",
    "void",
    ["map", "string", "string" ]];
}
sub InitConstants {

    my $security = $_[0];

    $min_uid{"local"}	= $security->{"UID_MIN"};
    $max_uid{"local"}	= $security->{"UID_MAX"};

    $min_uid{"system"}	= $security->{"SYSTEM_UID_MIN"};
    $max_uid{"system"}	= $security->{"SYSTEM_UID_MAX"};

    $min_gid{"system"}	= $security->{"SYSTEM_GID_MIN"};
    $max_gid{"system"}	= $security->{"SYSTEM_GID_MAX"};
}


##------------------------------------
sub ReadUsers {

    my $type	= $_[0];

    my $path 	= ".passwd.$type";
    if ($type eq "ldap") {
	$path 		= ".ldap";
        %userdns	= %{SCR::Read (".ldap.users.userdns")};
#	$user_items{$type}	= \%{SCR::Read ("$path.users.items")};
# FIXME looks like Perl cannot recognize YCPTerm... (?)
    }
    elsif ($type eq "nis") {
	$path		= ".nis";
    }
    else { # only local/system
	$last_uid{$type}= SCR::Read ("$path.users.last_uid");
    }

    $homes{$type} 	= \%{SCR::Read ("$path.users.homes")};
    $usernames{$type}	= \%{SCR::Read ("$path.users.usernames")};
    $uids{$type}	= \%{SCR::Read ("$path.users.uids")};

    return 1;
}

##------------------------------------
sub ReadGroups {

    my $type	= $_[0];
    my $path 	= ".passwd.$type";
    if ($type eq "ldap") {
	$path 	= ".$type";
#FIXME	$group_items{$type}	= \%{SCR::Read ("$path.groups.items")};
    }
    elsif ($type eq "nis") {
	$path 	= ".$type";
    }
    $gids{$type}	= \%{SCR::Read ("$path.groups.gids")};
    $groupnames{$type}	= \%{SCR::Read ("$path.groups.groupnames")};
#    $group_items{$type}	= \%{SCR::Read ("$path.groups.items")};
}


##------------------------------------
BEGIN { $TYPEINFO{Read} = ["function", "void"];}
sub Read {

    # read cache data for local & system: passwd agent:
    ReadUsers ("local");
    ReadUsers ("system");

    ReadGroups ("local");
    ReadGroups ("system");
}

##-------------------------------------------------------------------------

BEGIN { $TYPEINFO{BuildAdditional} = ["function",
    ["list", "term"],
    ["map", "string", "any"]];
}
sub BuildAdditional {

    my $group		= $_[0];
    my @additional 	= ();
    my $true		= YaST::YCP::Boolean (1);
    my $false		= YaST::YCP::Boolean (0);
    
    foreach my $type (keys %usernames) {

	# LDAP groups can contain only LDAP users...
	if ($group_type eq "ldap" && $type ne "ldap") {
	    next;
	    # TODO LDAP users are identified by DN's, not by names!
	}

	foreach my $user (keys %{$usernames{$type}}) {
	
	    my $id = YaST::YCP::Term ("id", $user);
	    
	    if (defined $group->{"userlist"}{$user}) {

		push @additional, YaST::YCP::Term ("item", $id, $user, $true);
	    }
	    elsif (!defined $group->{"more_users"}{$user}) {
		push @additional, YaST::YCP::Term ("item", $id, $user, $false);
	    }
	}
    }

    return @additional;

}


# EOF
