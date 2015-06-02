Page = require "../Page"
SurveyPage = require "./SurveyPage"
forms = require '../forms'
mwaterforms = require 'mwater-forms'
ResponseModel = require('mwater-forms').ResponseModel

# Creates a new survey from a list
# Pass in site option (code of site) to specify a site to prefill in survey
module.exports = class NewSurveyPage extends Page
  constructor: (options) ->
    super(options)

    # Debounce creation for issue https://github.com/mWater/mwater-portal/issues/303
    @startSurvey = _.debounce(@startSurvey, 1000, true)

  @canOpen: (ctx) -> ctx.auth.insert("responses")

  events: 
    "click .survey" : "startSurvey"

  activate: ->
    @setTitle T("Select Survey")

    enumerators = [ "all", "user:" + @login.user ].concat(_.map(@login.groups, (g) -> "group:" + g))

    # Find forms deployed to me that are not deleted
    filter = { 
      deployments: { $elemMatch: { enumerators: { $in: enumerators }, active: true } } 
      state: { $ne: "deleted" } 
    }
    @db.forms.find(filter).fetch (forms) =>
      # If site-specific, filter by having a site question
      if @options.site
        forms = @filterToSiteForms(forms)

      @forms = forms
      data = _.map forms, (form) =>
        return  {
          _id: form._id
          name: mwaterforms.formUtils.localizeString(form.design.name, @localizer.locale)
        }
      @$el.html require('./NewSurveyPage.hbs')(forms:data)
    , @error

  startSurvey: (ev) =>
    surveyId = ev.currentTarget.id

    form = _.findWhere(@forms, { _id: surveyId })
    if not form
      @error(T("Form not found"))
      return

    response = {}
    responseModel = new ResponseModel(response: response, form: form, user: @login.user, groups: @login.groups) 
    responseModel.draft()

    # Fill in first site question
    if @options.site
      # Get first site question
      siteQuestion = @findFirstSiteQuestion(form)
      if siteQuestion
        response.data[siteQuestion._id] = { value: { code: @options.site }}

    @db.responses.upsert response, (response) =>
      @pager.closePage(SurveyPage, {_id: response._id, mode: "new"})
    , @error

  # Restricts the list to forms with a site question
  filterToSiteForms: (forms) =>
    return _.filter forms, (form) => @findFirstSiteQuestion(form)?

  # Finds the first site question in the form
  findFirstSiteQuestion: (form) =>
    for question in mwaterforms.formUtils.priorQuestions(form.design)
      if question._type == "SiteQuestion"
        return question
    return null

