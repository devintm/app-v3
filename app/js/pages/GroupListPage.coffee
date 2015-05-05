Page = require("../Page")

# Lists groups of which user is a member
module.exports = class GroupListPage extends Page
  @canOpen: (ctx) -> ctx.login?

  events: 
    'click .leave-group' : 'leaveClicked'

  create: ->
    @setTitle T('Groups')

    @render()

  render: ->
    # Query list of groups
    @db.groups.find({ member: true}, {interim: false}).fetch (groups) =>
      @groups = groups

      # Display list
      @$el.html require('./GroupListPage.hbs')(groups: groups)
    , @error


  leaveClicked: (ev) ->
    groupId = $(ev.currentTarget).data("id")
    console.log groupId

    # Find group
    group = _.findWhere(@groups, { _id: groupId })

    if group.admin
      @db.group_members.find({ group: group.groupname, admin: true }, {interim: false}).fetch (adminGroupMembers) =>
        if adminGroupMembers.length <= 1
          alert("You can't leave that group since you are its only admin.")
          return
        @leaveGroup(group)
    else
      @leaveGroup(group)

  leaveGroup: (group) ->
    if not confirm(T("Leave the group '{0}'? Only a group admin can re-add you.", group.groupname))
      return

    @db.group_members.find({ group: group.groupname, member: "user:" + @login.user}, {interim: false}).fetch((groupMembers) =>
      if groupMembers.length == 1
        @db.remoteDb.group_members.remove(groupMembers[0]._id, () =>
          if @updateGroupsList
            @updateGroupsList()
          @render()
        , @error)
    , @error)


