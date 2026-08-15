#!/usr/bin/env perl
use strict;
use warnings;
use Gtk3 -init;
use JSON::PP;
use Socket qw(inet_pton AF_INET AF_INET6);# for ip syntax validation, no network

my $home_dir = (getpwuid $<)[7] || $ENV{HOME} || '';
die "impossible to find user home directory\n" unless $home_dir;
my $json_path = "$home_dir/.fvwm/ssh_sessions.json";

my %existing_names;
my %existing_hosts;

if (-f $json_path) {
    if (open my $fh, '<', $json_path) {
        local $/;
        my $content = <$fh>;
        close $fh;
        my $parsed = eval { decode_json($content); };
        if ($parsed && ref($parsed) eq 'HASH') {
            while (my ($k, $v) = each %$parsed) {
                $existing_names{lc($k)} = 1;
                my $h = ref($v) eq 'HASH' ? $v->{host} : $v;
                if ($h) {
                    $existing_hosts{lc($h)} = $k;
                }
            }
        }
    }
}

my $styles = <<'CSS';
* {
	font-family: "Terminus", monospace;
	font-size: 11px;
}
CSS

my $screen = Gtk3::Gdk::Screen::get_default();
my $css = Gtk3::CssProvider->new();

Gtk3::StyleContext::add_provider_for_screen($screen, $css, 600);
$css->load_from_data($styles);

my $window = Gtk3::Window->new('toplevel');
$window->set_title('Adding new ssh session');
$window->set_position('center');
$window->set_default_size(350, 350);
$window->signal_connect(destroy => sub { Gtk3::main_quit });

my $grid = Gtk3::Grid->new;
#$grid->set_margin_start(15);
#$grid->set_margin_end(15);
#$grid->set_margin_top(15);
#$grid->set_margin_bottom(15);
$grid->set_property('margin', 15);
$grid->set_row_spacing(10);
$grid->set_column_spacing(10);
$window->add($grid);

my @labels = ("Name on the list", "Host or IP address", "Username on dest system", "Port");
my @entries;

for my $i (0 .. $#labels) {
    my $label = Gtk3::Label->new($labels[$i]);
    $label->set_xalign(0);
    my $entry = Gtk3::Entry->new();
    
    $grid->attach($label, 0, $i, 1, 1);
    $grid->attach($entry, 1, $i, 1, 1);
    push @entries, $entry;
}

# Auth Method Selection Combo Box
my $auth_label = Gtk3::Label->new("Auth method");
$auth_label->set_xalign(0);
my $auth_combo = Gtk3::ComboBoxText->new();
$auth_combo->append_text("Anonymous");
$auth_combo->append_text("Password");
$auth_combo->append_text("Identity File");

$grid->attach($auth_label, 0, 4, 1, 1);
$grid->attach($auth_combo, 1, 4, 1, 1);

# Dynamic Auth Widget Container (Password Entry vs File Chooser)
my $auth_val_label = Gtk3::Label->new("credential");
$auth_val_label->set_xalign(0);
$auth_val_label->set_no_show_all(1);

my $pass_entry = Gtk3::Entry->new();
$pass_entry->set_visibility(0); # Masks characters with dots/stars

my $file_button = Gtk3::FileChooserButton->new("Select Identity File", 'open');

my $auth_stack = Gtk3::Stack->new();
$auth_stack->add_named($pass_entry, "password");
$auth_stack->add_named($file_button, "identity");
$auth_stack->set_visible_child_name("password");

$grid->attach($auth_val_label, 0, 5, 1, 1);
$grid->attach($auth_stack, 1, 5, 1, 1);

# Real-time validation error/status label
my $error_label = Gtk3::Label->new("");
$error_label->set_xalign(0);
$error_label->set_markup("<span foreground='red'>Name and Host at least are required.</span>");
$grid->attach($error_label, 0, 6, 2, 1);

my $button_box = Gtk3::ButtonBox->new('horizontal');
$button_box->set_layout('spread');
$grid->attach($button_box, 0, 7, 2, 1);

my $save_btn   = Gtk3::Button->new('Save');
my $cancel_btn = Gtk3::Button->new('Cancel');
$save_btn->set_sensitive(0); # Disabled by default
$button_box->pack_start($save_btn, 1, 1, 0);
$button_box->pack_start($cancel_btn, 1, 1, 0);

$cancel_btn->signal_connect(clicked => sub {
    Gtk3::main_quit;
});

# Toggle dynamic input fields based on Auth Method selection
$auth_combo->signal_connect(changed => sub {
    my $active = $auth_combo->get_active;
    if ($active == 0) { # None
        $auth_val_label->hide();
        $auth_stack->hide();
    } elsif ($active == 1) { # Password
        $auth_val_label->set_text("Password");
        $auth_val_label->show();
        $auth_stack->set_visible_child_name("password");
        $auth_stack->show();
    } elsif ($active == 2) { # Identity File
        $auth_val_label->set_text("Identity File");
        $auth_val_label->show();
        $auth_stack->set_visible_child_name("identity");
        $auth_stack->show();
    }
    validate_form();
});
$auth_combo->set_active(0);

sub validate_form {
    my $name = $entries[0]->get_text;
    my $host = $entries[1]->get_text;
    my $user = $entries[2]->get_text;
    my $port = $entries[3]->get_text;
    my $auth_type = $auth_combo->get_active;

    if (!length($name)) {
        $error_label->set_markup("<span foreground='red'>name is required.</span>");
        $save_btn->set_sensitive(0);
        return;
    }

    if (exists $existing_names{lc($name)}) {
        $error_label->set_markup("<span foreground='red'>name already exists.</span>");
        $save_btn->set_sensitive(0);
        return;
    }

    if (!length($host)) {
        $error_label->set_markup("<span foreground='red'>IP is required.</span>");
        $save_btn->set_sensitive(0);
        return;
    }

    if (exists $existing_hosts{lc($host)}) {
        my $matched_session = $existing_hosts{lc($host)};
        $error_label->set_markup("<span foreground='red'>IP used in '$matched_session'.</span>");
        $save_btn->set_sensitive(0);
        return;
    }

    my $is_ip = 0;
    $is_ip = 1 if defined inet_pton(AF_INET, $host);
    $is_ip = 1 if defined inet_pton(AF_INET6, $host);
    my $is_hostname=($host=~/^[a-zA-Z0-9][-a-zA-Z0-9.]*[a-zA-Z0-9]$/ && $host !~ /^\d+$/);

    if (!$is_ip && !$is_hostname) {
        $error_label->set_markup("<span foreground='red'>IP/hostname didnt match validate</span>");
        $save_btn->set_sensitive(0);
        return;
    }

    if (length($port)) {
        if ($port !~ /^\d+$/ || $port < 1 || $port > 65535) {
            $error_label->set_markup("<span foreground='red'>Port has to be >=1 <=65535</span>");
            $save_btn->set_sensitive(0);
            return;
        }
    }

    if ($auth_type == 1) {
        my $pass = $pass_entry->get_text;
        if (!length($pass)) {
            $error_label->set_markup("<span foreground='red'>Password cannot be empty.</span>");
            $save_btn->set_sensitive(0);
            return;
        }
    } elsif ($auth_type == 2) {
        my $filename = $file_button->get_filename;
        if (!defined $filename || !-f $filename) {
            $error_label->set_markup("<span foreground='red'>Invalid identity file.</span>");
            $save_btn->set_sensitive(0);
            return;
        }
    }

    my $status_msg = length($port) ? "Valid (Port: $port)" : "Valid configuration";
    $error_label->set_markup("<span foreground='green'>&#x2713; $status_msg</span>");
    $save_btn->set_sensitive(1);
}

for my $entry (@entries) {
    $entry->signal_connect(changed => \&validate_form);
}
$pass_entry->signal_connect(changed => \&validate_form);
$file_button->signal_connect('file-set' => \&validate_form);

$save_btn->signal_connect(clicked => sub {
    my $name = $entries[0]->get_text;
    my $host = $entries[1]->get_text;
    my $user = $entries[2]->get_text;
    my $port = $entries[3]->get_text;
    my $auth_type = $auth_combo->get_active;

    my $root = {};
    if (-f $json_path) {
        if (open my $fh, '<', $json_path) {
            local $/;
            my $content = <$fh>;
            close $fh;
            eval { $root = decode_json($content); };
        }
    }

    my $pass = $pass_entry->get_text;
    my $identity = $file_button->get_filename;

    if (length($user) || length($port) || ($auth_type == 1 && length($pass))
	    || ($auth_type == 2 && defined $identity)) {
        my %obj = ( host => $host );
        $obj{user} = $user if length($user);
        $obj{port} = int($port) if length($port);
        $obj{password} = $pass if ($auth_type == 1 && length($pass));
        $obj{identity_file} = $identity if ($auth_type == 2 && defined $identity);
        $root->{$name} = \%obj;
    } else {
        $root->{$name} = $host;
    }

    my $json = JSON::PP->new->ascii->pretty->canonical;
    my $pretty_json = $json->encode($root);

    if (open my $fh, '>', $json_path) {
        print $fh $pretty_json;
        close $fh;
    }

    Gtk3->main_quit;
});

$window->show_all;
Gtk3::main;

