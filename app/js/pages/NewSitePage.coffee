Page = require '../Page'
forms = require 'mwater-forms'
SitePage = require "./SitePage"
commonUI = require './commonUI'
GeoJSON = require '../GeoJSON'

# Allows creating of a site
# Options include
# geo: to initialize the geo of the site
# onSelect - function to call with site doc when selected
# filterSiteTypes: list of site types to include. null for all
module.exports = class NewSitePage extends Page
  @canOpen: (ctx) -> ctx.auth.insert("sites")

  events:
    "click #create_site": "createSite"
    "click #cancel": "cancel"
    "click #show_attrs": -> 
      @$("#site_attr_questions").show()
      @$("#show_attrs").hide()

  create: ->
    @setTitle T("New Site")

    @$el.html require('./NewSitePage.hbs')()

    # Create model for the site
    @siteModel = new Backbone.Model({ 
      location: { value: @options.location }
      privacy: {}
      name: {}
      desc: {}
      type: {}
      group: { value: _.first(@login.groups) }
    })
    
    # Default WaterAid to private
    if _.any(@login.groups, (g) -> g.match(/wateraid/i))
      @siteModel.set("privacy", { value: "private" })

    siteQuestions = commonUI.createBasicSiteQuestions(@siteModel, @ctx, @options.filterSiteTypes, true)

    siteQuestions.push new forms.RadioQuestion
      id: 'privacy'
      model: @siteModel
      prompt: T("Site privacy")
      choices: [
        { id: "public", label: T("Public"), hint: T("Anyone can see and edit the site")}
        { id: "visible", label: T("Visible"), hint: T("Anyone can see the site, but only you or your group can see and edit it")}
        { id: "private", label: T("Private"), hint: T("Only you or your group can see or edit site")}
      ]
      required: true
      hint: T('Private should only be used for sites that are not publicly accessible')

    if @login.groups.length > 0
      choices = [{ id: "(none)", label: T("(No Group)") }]
      choices = choices.concat(_.map(@login.groups, (g) => { id: g, label: g }))
      siteQuestions.push new forms.DropdownQuestion
        id: 'group'
        model: @siteModel
        prompt: T("Create site for group")
        required: true
        choices: choices

    @siteQuestionsGroup = new forms.QuestionGroup(contents: siteQuestions)

    @$("#site_questions").append(@siteQuestionsGroup.el)

    # Create site attributes model from site
    updateSiteAttrQuestions = =>
      if @siteAttrQuestionsGroup
        @siteAttrQuestionsGroup.remove()

      @siteAttrModel = new Backbone.Model()
      siteAttrQuestions = commonUI.createSiteAttributeQuestions(@getSiteType(), @siteAttrModel)
      @siteAttrQuestionsGroup = new forms.QuestionGroup(contents: siteAttrQuestions)
      @$("#site_attr_questions").append(@siteAttrQuestionsGroup.el)

      # Reset visibility
      @$("#site_attr_questions").hide()

      # Only show display buttons if currently hidden and there are some to show
      @$("#show_attrs").toggle(siteAttrQuestions.length > 0 and not @$("#site_attr_questions").is(":visible"))

    updateSiteAttrQuestions()

    # When type changes, reset attrs
    @siteModel.on "change:type change:subtype", () =>
      # Reset attributes
      updateSiteAttrQuestions()

  getSiteType: =>
    type = []
    type[0] = @siteModel.get("type").value
    if @siteModel.get("subtype") and @siteModel.get("subtype").value
      type[1] = @siteModel.get("subtype").value
    return type

  createSite: ->
    # First validate
    if not @siteQuestionsGroup.validate() or not @siteAttrQuestionsGroup.validate()
      alert(T("Please correct values"))
      return

    site = {
      photos: []
      tags: []
    }

    site.name = @siteModel.get("name").value
    site.desc = @siteModel.get("desc").value

    site.type = @getSiteType()
    site.type[0] = @siteModel.get("type").value
    if @siteModel.get("subtype") and @siteModel.get("subtype").value
      site.type[1] = @siteModel.get("subtype").value

    site.location = @siteModel.get("location").value
    if site.location
      site.geo = GeoJSON.locToPoint(site.location)
    else
      delete site.location

    site.attrs = @siteAttrModel.toJSON()

    # Set group
    group = @siteModel.get("group").value
    if group == "(none)"
      group = null

    # Set who created for
    site.created = { by: @login.user }
    if group
      site.created.for = group

    # Set roles based on privacy
    if @siteModel.get("privacy").value == "public"
      site.roles = [ { id: "all", role: "admin" } ]
    if @siteModel.get("privacy").value == "visible"
      site.roles = [ { id: "all", role: "view" } ]
    else
      site.roles = [ ]

    if group
      site.roles.push { id: "group:#{group}", role: "admin" }
    else
      site.roles.push { id: "user:#{this.login.user}", role: "admin" }

    success = (code) =>
      site.code = code

      @db.sites.upsert site, (site) => 
        @pager.closePage(SitePage, { _id: site._id, onSelect: @options.onSelect })
      , @error

    error = =>
      alert(T("Unable to generate site id. Please ensure that you have a connection or use Settings to obtain more before going out of connection range."))

    @siteCodesManager.requestCode(success, error)

  cancel: ->
    @pager.closePage()
