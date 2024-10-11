module main

import regex
import os
import json
import readline
import time
import toml
import rand

import ismyhc.vnostr

const nip_29_kinds = [9, 10, 11, 12, 9000, 9001, 9002, 9003, 9004, 9005, 9006, 9007, 9008, 9021, 9022, 39000, 39001, 39002, 39003]

fn main() {

    exec_path := os.executable()
    exec_dir := os.dir(exec_path)

	doc := toml.parse_file('${exec_dir}/vstrfryn29.toml') or { panic(err) }
	
	// Put strfry_cmd_path in the toml file. If you've exported your strfry executable
	// in your path, you can leave it ast 'strfry' otherwise it should be the full path
	// to the strfry executable
	strfry_cmd := doc.value('strfry_cmd_path').string()
	if strfry_cmd == '' {
		mut stderr := os.stderr()
		stderr.write_string('strfry command from toml file cannot be empty')!
		panic('Goodbye') 
	}

	// vstrfryn29.toml should be placed in same dir as vstrfryn29 executable
	// Put pk_hex = 'private key hex'
	pk_hex := doc.value('pk_hex').string()
	kp := vnostr.VNKeyPair.from_private_key_hex(pk_hex) or { 
		mut stderr := os.stderr()
		stderr.write_string('Unable to parse private key hex: ${err.str()}')!
		panic(err) 
	}

	group_creation_difficulty := doc.value('group_creation_difficulty').int()
	reject_events_newer_than := doc.value('reject_events_newer_than').int() * -1
	reject_events_older_than := doc.value('reject_events_older_than').int()

	mut r := readline.Readline{}

	for {
		entered := r.read_line('') or { continue }

		input_msg := json.decode(InputMessage, entered) or {
			mut stderr := os.stderr()
			stderr.write_string('could not decode input message') or { continue }
			continue
		}

		if input_msg.@type != 'new' {
			reject('unexpected request type', input_msg.event.id)
			continue
		}

		event_id := input_msg.event.id
		kind := input_msg.event.kind

		if kind in nip_29_kinds {

			// Validate event since we could trigger other events
			// to be created like 39000,39001,39002
			if input_msg.event.valid_signature() == false {
				reject('invalid event', input_msg.event.id)
				continue
			}

			mut group_id := get_group_id(input_msg.event) or {
				// We will allow create group to not pass a group id
				// then we will just create a random ulid
				if kind == 9007 {
					rand.ulid()
				} else {
					reject(err.str(), event_id)
					continue
				}
			}

			current_time := time.now().unix()

			time_delta := input_msg.event.created_at - current_time
			
			if time_delta < reject_events_newer_than {
				reject('Event created_at is to far in the future', input_msg.event.id)
				continue
			}

			if time_delta > reject_events_older_than {
				reject('Event created_at is to old', input_msg.event.id)

				continue
			}

			pubkey := input_msg.event.pubkey

			match kind {
				9...12 { // chat message, etc : DONE

					if is_member(group_id, pubkey, strfry_cmd) == false { // Is member also checks groups existance.
						reject('${pubkey}not a member of ${group_id}', event_id)
						continue
					}

					accept(event_id)
					continue

				}
				9000 { // add-user : DONE 

					if group_exists(group_id, strfry_cmd) == false {
						reject('${group_id} does not exsit', event_id)
						continue
					}

					requestor_role := has_role_power(group_id, pubkey, strfry_cmd)
					if requestor_role.power() < GroupRole.moderator.power() {
						reject('${pubkey} does not have permission to add user to group ${group_id}', event_id)
						continue
					}

					pubkey_to_add := get_pubkey_from_request_event(input_msg.event) or { 
						reject('Couldnt find pubkey', event_id)
						continue
					}

					if is_member(group_id, pubkey_to_add, strfry_cmd) {
						reject('${pubkey_to_add} already a member of ${group_id}', event_id)
						continue
					}

					// Cleanup join/leave requests
					_ := remove_join_request(group_id, pubkey_to_add, strfry_cmd)
					_ := remove_leave_request(group_id, pubkey_to_add, strfry_cmd)

					accept(event_id)
					continue

				}
				9001 { // remove-user : DONE 

					if group_exists(group_id, strfry_cmd) == false {
						reject('${group_id} does not exsit', event_id)
						continue
					}

					pubkey_to_remove := get_pubkey_from_request_event(input_msg.event) or { 
						reject('Couldnt find pubkey', event_id)
						continue
					}

					if is_member(group_id, pubkey_to_remove, strfry_cmd) == false {
						reject('${pubkey_to_remove} not a member', event_id)
						continue
					}

					requestor_power := has_role_power(group_id, pubkey, strfry_cmd)
					pubkey_to_remove_power := has_role_power(group_id, pubkey_to_remove, strfry_cmd)

					if requestor_power.power() < pubkey_to_remove_power.power() {
						reject('${pubkey} doesnt have authority to remove ${pubkey_to_remove_power}', event_id)
						continue
					}

					// Cleanup join/leave requests
					_ := remove_join_request(group_id, pubkey_to_remove, strfry_cmd)
					_ := remove_leave_request(group_id, pubkey_to_remove, strfry_cmd)

					accept(event_id)
					continue
				}
				9002 { // edit-metadata : DONE

					group := get_group(group_id, strfry_cmd) or {
						reject('${group_id} does not exsit', event_id)
						continue
					}

					requestor_role := has_role_power(group_id, pubkey, strfry_cmd)
					if requestor_role.power() < GroupRole.admin.power() {
						reject('${pubkey} does not have permission to edit-metadata for group ${group_id}', event_id)
						continue
					}

					mut current_tags := group.tags.clone()

					current_name_tag := current_tags.filter(it.len == 2 && it[0] == 'name')
					mut name := ""
					if current_name_tag.len > 0 {
						if current_name_tag[0].len == 2 {
							name = current_name_tag[0][1]
						}
					} 

					current_picture_tag := current_tags.filter(it.len == 2 && it[0] == 'picture')
					mut picture := ""
					if current_picture_tag.len > 0 {
						if current_picture_tag[0].len == 2 {
							picture = current_picture_tag[0][1]
						}
					} 

					current_about_tag := current_tags.filter(it.len == 2 && it[0] == 'about')
					mut about := ""
					if current_about_tag.len > 0 {
						if current_about_tag[0].len == 2 {
							about = current_about_tag[0][1]
						}
					} 

					//mut private := tags.filter(it.len == 1 && it[0] == 'private').len > 0
					mut closed := current_tags.filter(it.len == 1 && it[0] == 'closed').len > 0
					
					// Now start overwriting data that is new
					new_name_tag := input_msg.event.tags.filter(it.len == 2 && it[0] == 'name')
					if new_name_tag.len > 0 {
						if new_name_tag[0].len == 2 {
							name = new_name_tag[0][1]
						}
					} 

					new_picture_tag := input_msg.event.tags.filter(it.len == 2 && it[0] == 'picture')
					if new_picture_tag.len > 0 {
						if new_picture_tag[0].len == 2 {
							picture = new_picture_tag[0][1]
						}
					} 

					new_about_tag := input_msg.event.tags.filter(it.len == 2 && it[0] == 'about')
					if new_about_tag.len > 0 {
						if new_about_tag[0].len == 2 {
							about = new_about_tag[0][1]
						}
					} 

					//private := input_msg.event.tags.filter(it.len == 1 && it[0] == 'private').len > 0
					closed = input_msg.event.tags.filter(it.len == 1 && it[0] == 'closed').len > 0

					mut new_tags := [][]string{}
					new_tags << ["d", group_id]
					new_tags << ["name", name]
					new_tags << ["picture", picture]
					new_tags << ["about", about]
					//if private { new_tags << ["private"] } else { new_tags << ["public"] } // TODO: Add private support
					new_tags << ["public"]
					if closed { new_tags << ["closed"] } else { new_tags << ["open"] }

					signed_event := update_group_metadata_event(new_tags, u64(current_time), kp) or {
						reject(err.str(), event_id)
						continue
					}

					if import_event(signed_event, strfry_cmd) == false {
						reject('there was a updating metadata', event_id)
						continue
					}

					accept(event_id)
					continue

				}
				9003 { // add-permission : OLD LETS REJECT
					reject('Old nip29. You are rejected!', event_id) 
					continue
				}
				9004 { // remove-permission : OLD LETS REJECT
					reject('Old nip29. You are rejected!', event_id) 
					continue
				}
				9005 { // delete-event : TODO
					reject('functionality not implemented yet', event_id)
					continue
				}
				9006 { // set-role : TODO

					// if group_exists(group_id, strfry_cmd) == false {
					// 	reject('${group_id} does not exsit', event_id)
					// 	continue
					// }

					// requestor_role := has_role_power(group_id, pubkey, strfry_cmd)

					// if requestor_role.power() < GroupRole.admin.power() {
					// 	reject('${pubkey} does not have permission to set-role for group ${group_id}', event_id)
					// 	continue
					// }

					// requested_role_entry := extract_role_from_tags(input_msg.event.tags)
					// if requested_role_entry.len != 3 {
					// 	reject('Missing required fields to set-role', event_id)
					// 	continue
					// }

					// requested_role := group_role_from_string(requested_role_entry[2])
					// if requested_role == GroupRole.member { // This means no valid role found
					// 	reject('role not valid', event_id)
					// 	continue
					// }

					// if requested_role.power() > requestor_role.power() {
					// 	reject('Cannot set-role above your role', event_id)
					// 	continue
					// }

					// pubkey_to_modify := requested_role_entry[1]
					// if vnostr.valid_public_key_hex(pubkey_to_modify) == false {
					// 	reject('pubkey not valid', event_id)
					// 	continue
					// }

					// // who are we changing?
					// pubkey_to_modify_role := has_role_power(group_id, pubkey_to_modify, strfry_cmd)
					// if requested_role.power() < pubkey_to_modify_role.power() {
					// 	// No beuno
					// 	reject('Cannot set-role of pubkey above your role', event_id)
					// 	continue
					// }

					// if pubkey_to_modify_role == GroupRole.member {
					// 	// Just add to admins list
					// } else {
					// 	// Need to find the entry and replace it
					// }

					reject('functionality not implemented yet', event_id)
					continue
				}
				9007 { // create-group : DONE

					if group_exists(group_id, strfry_cmd) {
						reject('${group_id} group already exsits', event_id)
						continue
					}

					if group_creation_difficulty > 0 {
						if input_msg.event.pow_difficulty() < group_creation_difficulty {
							reject('${group_id} group creation requires pow difficulty of ${group_creation_difficulty}', event_id)
							continue
						}
					}

					signed_metadata_event := new_group_metadata_event(group_id, u64(current_time), kp) or {
						reject('${group_id} failed ${err.str()}', event_id)
						continue
					}

					signed_roles_event := new_group_roles_event(group_id, u64(current_time), kp) or {
						reject('${group_id} failed ${err.str()}', event_id)
						continue
					}

					signed_admins_event := new_group_admins_event(group_id, pubkey, u64(current_time), kp) or {
						reject('${group_id} failed ${err.str()}', event_id)
						continue
					}

					signed_join_event := add_user_event(group_id, pubkey, u64(current_time), kp, strfry_cmd) or {
						reject('${group_id} failed ${err.str()}', event_id)
						continue
					}

					if import_event(signed_metadata_event, strfry_cmd) == false {
						reject('there was a problem creating group', event_id)
						continue
					}

					if import_event(signed_roles_event, strfry_cmd) == false {
						reject('there was a problem creating admins', event_id)
						continue
					}

					if import_event(signed_admins_event, strfry_cmd) == false {
						reject('there was a problem creating group', event_id)
						continue
					}

					if import_event(signed_join_event, strfry_cmd) == false {
						reject('there was a problem creating admins', event_id)
						continue
					}

					accept(event_id)
					continue

				}
				9008 { // delete-group : DONE
					if group_exists(group_id, strfry_cmd) == false {
						reject('${group_id} does not exsit', event_id)
						continue
					}

					requestor_role := has_role_power(group_id, pubkey, strfry_cmd)
					if requestor_role.power() < GroupRole.owner.power() {
						reject('${pubkey} does not have permission to delete group ${group_id}', event_id)
						continue
					}

					if delete_group(group_id, strfry_cmd) == false {
						reject('Something happened deleting group ${group_id}', event_id)
						continue
					}

					accept(event_id) // TODO: Maybe need to make a timed function that deletes this event after accepting...
					continue
				}
				9021 { // join request : DONE

					pubkey_to_add := get_pubkey_from_request_event(input_msg.event) or { 
						reject('Couldnt find pubkey', event_id)
						continue
					}

					if pubkey_to_add != pubkey {
						reject('Pubkeys dont match.', event_id)
						continue
					}

					if is_member(group_id, pubkey_to_add, strfry_cmd) {
						reject('${pubkey}already a member of ${group_id}', event_id)
						continue
					}

					private, closed := get_group_status(group_id, strfry_cmd) or {
						reject('${group_id} group does not exsit', event_id)
						continue
					}

					// If group is private or closed we allow the request, but
					// a group member with the correct role can simply add-user
					// for this request
					if private || closed {
						accept(event_id)
						continue
					}

					signed_join_event := add_user_event(group_id, pubkey_to_add, u64(current_time), kp, strfry_cmd) or {
						reject('${group_id} failed ${err.str()}', event_id)
						continue
					}

					if import_event(signed_join_event, strfry_cmd) == false {
						reject('there was a problem joining', event_id)
						continue
					}

					accept(event_id)
					continue
				}
				9022 { // leave request : DONE

					// TODO: Check if user is admin
					// Should we let them leave if they are the only admin?
					// If they arent the only one, we need to remove them
					// from admin list as well.

					pubkey_to_remove := get_pubkey_from_request_event(input_msg.event) or { 
						reject('Couldnt find pubkey', event_id)
						continue
					}

					if pubkey_to_remove != pubkey {
						reject('Pubkeys dont match.', event_id)
						continue
					}

					if is_member(group_id, pubkey_to_remove, strfry_cmd) == false {
						reject('${pubkey} not a member ${group_id}', event_id)
						continue
					}

					signed_leave_event := remove_user_event(group_id, pubkey_to_remove, u64(current_time), kp, strfry_cmd) or {
						reject('${group_id} failed ${err.str()}', event_id)
						continue
					}

					if import_event(signed_leave_event, strfry_cmd) == false {
						reject('there was a problem leaving', event_id)
						continue
					}

					accept(event_id)
					continue
				}
				39000...39003 { // : DONE : group-metadata, group-admins, group-members : REJECT since this can only be changed by moderation events or relay
					reject('Kind ${input_msg.event.kind} cannot be created or modified directly', input_msg.event.id)
					continue
				}
				else { // Should never reach this
					reject('uknown type...', event_id)
					continue
				}
			}

		} else {

			// TODO: Here we can filter out any kinds we dont want to allow
			accept(event_id)
		}

	}
}

fn accept(id string) {
	mut res := OutputMessage{
		id:     id
		action: 'accept'
		msg:   	'' 
	}
	println(json.encode(res))
	os.flush()	
}

fn reject(msg string, id string) {
	mut res := OutputMessage{
		id:     id
		action: 'reject'
		msg:   	msg 
	}
	println(json.encode(res))
	os.flush()
}

fn import_event(e Event, strfry_cmd string) bool {
	command := "echo '${e.stringify()}' | ${strfry_cmd} import"
	result := os.execute(command)
	if result.exit_code != 0 {
		return false
	}
	return true
}

fn get_group_status(gid string, strfry_cmd string) !(bool, bool) {
	group := get_group(gid, strfry_cmd) or {
		return error('No group found for ${gid}')
	}
	
	private := group.tags.filter(it.len == 1 && it[0] == 'private').len > 0
	closed := group.tags.filter(it.len == 1 && it[0] == 'closed').len > 0

	return private, closed
}

fn get_group(gid string, strfry_cmd string) !Event {
	command := '${strfry_cmd} scan \'{"kinds": [39000], "#d":["${gid}"]}\''
	result := query_with_command(command)
	if result.len > 0 {
		return result[0]
	}
	return error('No group found for ${gid}')
}

fn group_exists(gid string, strfry_cmd string) bool {
	_ := get_group(gid, strfry_cmd) or {
		return false
	}
	return true
}

fn is_member(gid string, pubkey string, strfry_cmd string) bool {
	command := '${strfry_cmd} scan \'{"kinds": [9000,9001], "#h":["${gid}"], "#p": ["${pubkey}"]}\''
	result := query_with_command(command)
	if result.len == 0 {
		return false
	}
	return result.sorted(a.created_at > b.created_at)[0].kind == 9000
}

fn has_role_power(gid string, pubkey string, strfry_cmd string) GroupRole {
	command := '${strfry_cmd} scan \'{"kinds": [39001], "#d":["${gid}"], "#p": ["${pubkey}"]}\''
	result := query_with_command(command)
	if result.len == 0 {
		return GroupRole.member
	}
	
	filtered_tags := result[0].tags.filter(it.len > 2 && it[0] == "p" && it[1] == pubkey)
	if filtered_tags.len < 1 || filtered_tags[0].len < 3 {
		return GroupRole.member
	}

	mut role_strings := []string{}
	role_strings << filtered_tags[0][2..]

	if role_strings.len == 0 {
		return GroupRole.member
	}

	mut user_roles := []GroupRole{}
	for rs in role_strings {
		user_roles << group_role_from_string(rs)
	}

	// ascending and return the largest number
	user_roles.sort_with_compare(fn (a &GroupRole, b &GroupRole) int {
        return a.power() - b.power()
    })

	return user_roles.last()
}

fn extract_role_from_tags(tags [][]string) []string {
	filtered_tags := tags.filter(it.len > 2 && it[0] == "p")
	if filtered_tags.len < 1 || filtered_tags[0].len < 3 {
		return []
	}
	return filtered_tags[0][..3]
}

fn query_events_by_kind(kinds []int, strfry_cmd string) []Event {
	command := '${strfry_cmd} scan \'{"kinds": ${kinds.str()}}\''
	return query_with_command(command)
}

fn query_with_command(cmd string) []Event {
	result := os.execute(cmd)
	if result.exit_code != 0 {
		return []
	}

	lines := result.output.split_into_lines()
	mut events := []Event{}
	for line in lines {
		event := json.decode(Event, line) or { continue }
		events << event
	}
	return events
}

fn remove_join_request(gid string, pubkey string, strfry_cmd string) bool {
	command_a := '${strfry_cmd} delete \'{"kinds": [9021], "#h":["${gid}"], "#p": ["${pubkey}"]}\''
	_ := os.execute(command_a)
	return true
}

fn remove_leave_request(gid string, pubkey string, strfry_cmd string) bool {
	command_a := '${strfry_cmd} delete \'{"kinds": [9022], "#h":["${gid}"], "#p": ["${pubkey}"]}\''
	_ := os.execute(command_a)
	return true
}

fn delete_group(gid string, strfry_cmd string) bool {
	command_a := '${strfry_cmd} delete \'{"kinds": ${nip_29_kinds.str()}, "#d":["${gid}"]}\''
	_ := os.execute(command_a)
	command_b := '${strfry_cmd} delete \'{"kinds": ${nip_29_kinds.str()}, "#h":["${gid}"]}\''
	_ := os.execute(command_b)
	return true
}

fn valid_group_id(s string) bool {
    pattern := r'^[a-zA-Z0-9-_]+'
    mut re := regex.regex_opt(pattern) or {
        return false
    }
    return re.matches_string(s)
}

fn get_group_id(e Event) !string {
	tags := e.filter_tags_by_name("h")
	if tags.len == 0 || tags[0].len < 2 {
		return error('missing h tag or h tag id missing')
	}

	group_id := tags[0][1]
	if valid_group_id(group_id) == false {
		return error('group id not valid format')
	}
	return group_id
}

fn new_group_metadata_event(gid string, current_time u64, kp KeyPair) !Event {
	mut tags := [][]string{}
	tags << ["d", gid]
	tags << ["name", "New Group"]
	tags << ["picture", ""]
	tags << ["about", "A newley created group"]
	tags << ["public"]
	tags << ["open"]

	event := vnostr.VNEvent.new(pubkey: kp.public_key_hex, created_at: current_time, kind: 39000, tags: tags)
	signed_event := event.sign(kp) or { 
		return err
	}
	return signed_event
}

fn update_group_metadata_event(tags [][]string, current_time u64, kp KeyPair) !Event {
	event := vnostr.VNEvent.new(pubkey: kp.public_key_hex, created_at: current_time, kind: 39000, tags: tags)
	signed_event := event.sign(kp) or { 
		return err
	}
	return signed_event
}

fn new_group_roles_event(gid string, current_time u64, kp KeyPair) !Event {
	mut tags := [][]string{}
	tags << ["d", gid]

	// Add owner role
	mut owner_role := []string{}
	owner_role << GroupRole.owner.str()
	owner_role << "Owner"
	owner_role << "The owner role is like god mode for the group"
	owner_role << owner_permissions()
	tags << owner_role

	// Add admin role
	mut admin_role := []string{}
	admin_role << GroupRole.admin.str()
	admin_role << "Admin"
	admin_role << "The admin role can do everything except remove the owner, delete the group and change owner role"
	admin_role << admin_permissions()
	tags << admin_role

	// Add moderator role
	mut moderator_role := []string{}
	moderator_role << GroupRole.moderator.str()
	moderator_role << "Moderator"
	moderator_role << "The moderator role can do everything except remove the owner and admin, delete the group, edit metadata and change roles"
	moderator_role << moderator_permissions()
	tags << moderator_role

	event := vnostr.VNEvent.new(pubkey: kp.public_key_hex, created_at: current_time, kind: 39003, tags: tags)
	signed_event := event.sign(kp) or { 
		return err 
	}
	return signed_event
}

fn new_group_members_event(gid string, pubkey string, current_time u64, kp KeyPair) !Event {
	mut tags := [][]string{}
	tags << ["d", gid]
	tags << ["p", pubkey]
	event := vnostr.VNEvent.new(pubkey: kp.public_key_hex, created_at: current_time, kind: 39002, tags: tags)
	signed_event := event.sign(kp) or { 
		return err
	}
	return signed_event
}

fn new_group_admins_event(gid string, pubkey string, current_time u64, kp KeyPair) !Event {
	mut tags := [][]string{}
	tags << ["d", gid]
	tags << ["p", pubkey, GroupRole.owner.str()]
	event := vnostr.VNEvent.new(pubkey: kp.public_key_hex, created_at: current_time, kind: 39001, tags: tags)
	signed_event := event.sign(kp) or { 
		return err
	}
	return signed_event
}

fn add_user_event(gid string, pubkey string, current_time u64, kp KeyPair, strfry_cmd string) !Event {
	mut tags := [][]string{}
	tags << ["h", gid]
	tags << ["p", pubkey]
	event := vnostr.VNEvent.new(pubkey: kp.public_key_hex, created_at: current_time, kind: 9000, tags: tags)
	signed_event := event.sign(kp) or { 
		return err
	}
	return signed_event
}

fn remove_user_event(gid string, pubkey string, current_time u64, kp KeyPair, strfry_cmd string) !Event {
	mut tags := [][]string{}
	tags << ["h", gid]
	tags << ["p", pubkey]
	event := vnostr.VNEvent.new(pubkey: kp.public_key_hex, created_at: current_time, kind: 9001, tags: tags)
	signed_event := event.sign(kp) or { 
		return err
	}
	return signed_event
}

fn get_pubkey_from_request_event(e Event) !string {
	filterd_tags := e.tags.filter(it.len >= 2 && it[0] == 'p')
	if filterd_tags.len == 0 || filterd_tags[0].len < 2 {
		return error('No valid pubkey')
	}

	pubkey := filterd_tags.filter(it.len >= 2 && it[0] == 'p')[0][1]
	if vnostr.valid_public_key_hex(pubkey) == false {
		return error('No valid pubkey')
	}
	return pubkey
}

// Types

type Event = vnostr.VNEvent
type KeyPair = vnostr.VNKeyPair

struct InputMessage {
	@type       string @[json: 'type'] // using @type becuase type is a keyword in vlang. This allows it.
	event       Event  @[json: 'event']
	received_at i64    @[json: 'receivedAt']
	source_type string @[json: 'sourceType']
	source_info string @[json: 'sourceInfo']
}

struct OutputMessage {
	id string
mut:
	action string
	msg    string
}

enum GroupRole {
	owner
	admin
	moderator
	member // This just means no role. Doest mean user is a member. Need to also check that
}

fn group_role_from_string(role_str string) GroupRole {
	match role_str {
		"owner" { return GroupRole.owner }
		"admin" { return GroupRole.admin }
		"moderator" { return GroupRole.moderator }
		else { return GroupRole.member }
	}
}

fn (gr GroupRole) power() int {
	return match gr {
		.owner { 20 }
		.admin { 15 }
		.moderator { 10 }
		.member { 0 }
	}
}

fn (gr GroupRole) str() string {
	return match gr {
		.owner { 'owner' }
		.admin { 'admin' }
		.moderator { 'moderator' }
		.member { '' }
	}
}

fn all_roles() []string {
	roles := [
		GroupRole.owner.str(),
		GroupRole.admin.str(),
		GroupRole.moderator.str(),
		GroupRole.member.str()
	]
	return roles
}

fn group_permissions_by_role(gr GroupRole) []string {
	return match gr {
		.owner { owner_permissions() }
		.admin { admin_permissions() }
		.moderator { moderator_permissions() }
		.member { []string{} }
	}
}

enum GroupPermission {
    add_user
    remove_user
    edit_metadata
    delete_event
    delete_group
	set_role
}

fn (gp GroupPermission) str() string {
    return match gp {
        .add_user { 'add-user' }
        .remove_user { 'remove-user' }
        .edit_metadata { 'edit-metadata' }
        .delete_event { 'delete-event' }
        .delete_group { 'delete-group' }
		.set_role { 'set-role'}
    }
}

fn owner_permissions() []string {
	permissions := [
		GroupPermission.add_user.str(),
		GroupPermission.edit_metadata.str(),
		GroupPermission.delete_event.str(),
		GroupPermission.remove_user.str(),
		GroupPermission.delete_group.str(),
		GroupPermission.set_role.str()
	]
	return permissions
}

fn admin_permissions() []string {
	permissions := [
		GroupPermission.add_user.str(),
		GroupPermission.edit_metadata.str(),
		GroupPermission.delete_event.str(),
		GroupPermission.remove_user.str(), // Cannot remove owner
		GroupPermission.set_role.str() // Cannot change owner role
	]
	return permissions
}

fn moderator_permissions() []string {
	permissions := [
		GroupPermission.add_user.str(),
		GroupPermission.delete_event.str(),
		GroupPermission.remove_user.str(), // Cannot remove owner or admin
	]
	return permissions
}