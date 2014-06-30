Page = require "../Page"
forms = require '../forms'

class TestPage extends Page
  create: -> @render()

  render: ->
    @setTitle T("Water Test")

    # Get test
    @db.tests.findOne {_id: @options._id}, (test) =>
      if not test
        alert(T("Test not found"))
        return @pager.closePage()

      @test = test

      if @auth.remove("tests", @test)
        @setupContextMenu [ { glyph: 'remove', text: T("Delete Test"), click: => @removeTest() } ]
      else 
        @setupContextMenu [ ]

      # Get form
      @db.forms.findOne { type: "WaterTest", code: test.type }, (form) =>
        if not form
          alert T("Test form {0} not found", response.type)
          @pager.closePage()
          return

        # Render test page
        @$el.html require('./TestPage.hbs')(form: form, test: test)

        # Check if not completed and editable
        if not test.completed and @auth.update("tests", test)
          @formView = forms.instantiateView(form.views.edit, { ctx: @ctx })

          # Listen to events
          @listenTo @formView, 'change', @save
          @listenTo @formView, 'complete', @completed
          @listenTo @formView, 'close', @close
          @listenTo @formView, 'discard', @removeTest
        else
          @formView = forms.instantiateView(form.views.detail, { ctx: @ctx })

        # Add form view
        @$('#contents').append(@formView.el)

        if not @auth.update("tests", test)
          @$("#edit_button").hide()

        @formView.load @test.data
      , @error
    , @error

  events:
    "click #edit_button" : "edit"

  activate: ->
    # Do not reload as form may have launched another page
    # and needs to keep its state

  destroy: ->
    # Let know that saved if closed incompleted
    if @test and not @test.completed
      @pager.flash T("Test saved as draft.")

    # Remove test control
    if @formView?
      @formView.remove()

  edit: ->
    # Mark as incomplete
    @test.completed = null
    @db.tests.upsert @test, => 
      @render()
    , @error

  save: =>
    # Save to db
    @test.data = @formView.save()
    @db.tests.upsert @test, =>
      return
    , @error

  close: =>
    @save()
    @pager.closePage()

  completed: =>
    # Mark as completed
    @test.data = @formView.save()
    @test.completed = new Date().toISOString()

    @db.tests.upsert @test, => 
      @pager.closePage()
      @pager.flash T("Test completed successfully"), "success"
    , @error

  removeTest: ->
    if @auth.remove("tests", @test) and confirm(T("Permanently delete test?"))
      @db.tests.remove @test._id, =>
        @test = null
        @pager.closePage()
        @pager.flash T("Test deleted"), "warning"
      , @error

module.exports = TestPage