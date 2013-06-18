Page = require "../Page"
forms = require '../forms'

class TestPage extends Page
  constructor: (ctx, testId) ->
    super(ctx)
    @testId = testId

  create: ->
  activate: -> @render()

  render: ->
    @setTitle "Test" # TODO nicer title

    # Get test
    @db.tests.findOne {_id: @testId}, (test) =>
      @test = test

      # Get form
      @db.forms.findOne { type: "WaterTest", code: test.type }, (form) =>
        # Check if completed
        if not test.completed
          @formView = forms.instantiateView(form.views.edit, { ctx: @ctx })

          # Listen to events
          @listenTo @formView, 'change', @save
          @listenTo @formView, 'complete', @completed
          @listenTo @formView, 'close', @close
        else
          @formView = forms.instantiateView(form.views.detail, { ctx: @ctx })
  
        # TODO disable if non-editable
        @$el.html templates['pages/TestPage'](completed: test.completed, title: form.name)
        @$('#contents').append(@formView.el)

        @formView.load @test

  events:
    "click #edit_button" : "edit"

  deactivate: ->
    # TODO Save to be safe
    # @save()

  edit: ->
    # Mark as incomplete
    @test.completed = null
    @db.tests.upsert @test, => @render()

  save: =>
    # Save to db
    @test = @formView.save()
    @db.tests.upsert(@test)

  close: =>
    @save()
    @pager.closePage()

  completed: =>
    # Mark as completed
    @test.completed = new Date().toISOString()
    @db.tests.upsert @test, => @render()
    

module.exports = TestPage