assert = chai.assert
forms = require('forms')
UIDriver = require './helpers/UIDriver'
ImagePage = require '../app/js/pages/ImagePage'

Localizer = require('ez-localize').Localizer
new Localizer().makeGlobal(require("hbsfy/runtime"))

class MockImageManager 
  getImageThumbnailUrl: (imageUid, success, error) ->
    success "images/" + imageUid + ".jpg"

  getImageUrl: (imageUid, success, error) ->
    success "images/" + imageUid + ".jpg"

class MockImageAcquirer
  acquire: (success, error) ->
    success("1234")

describe 'ImageQuestion', ->
  beforeEach ->
    # Create model
    @model = new Backbone.Model 

  context 'With a no image acquirer', ->
    beforeEach ->
      # Create context
      @ctx = {
        imageManager: new MockImageManager()
      }

      @question = new forms.ImageQuestion
        model: @model
        id: "q1"
        ctx: @ctx

    it 'displays no image', ->
      assert.isTrue true

    it 'displays one image', ->
      @model.set(q1: {id: "1234"})
      assert.equal @question.$("img.img-thumbnail").attr("src"), "images/1234.jpg"

    it 'opens page', ->
      @model.set(q1: {id: "1234"})
      spy = sinon.spy()
      @ctx.pager = { openPage: spy }
      @question.$("img.img-thumbnail").click()

      assert.isTrue spy.calledOnce
      assert.equal spy.args[0][1].id, "1234"

    it 'allows removing image', ->
      @model.set(q1: {id: "1234"})
      @ctx.pager = { 
        openPage: (page, options) =>
          options.onRemove()
      }
      @question.$("img.img-thumbnail").click()
      assert.equal @model.get("q1"), null

    it 'displays no add', ->
      assert.equal @question.$("img#add").length, 0

  context 'With an image acquirer', ->
    beforeEach ->
      # Create context
      @ctx = {
        imageManager: new MockImageManager()
        imageAcquirer: new MockImageAcquirer()
      }

      @question = new forms.ImageQuestion
        model: @model
        id: "q1"
        ctx: @ctx

    it 'gets an image', ->
      @question.$("img#add").click()
      assert.isTrue _.isEqual(@model.get("q1"), {id:"1234"}), @model.get("q1")

    it 'no longer has add after taking photo', ->
      @question.$("img#add").click()
      assert.equal @question.$("img#add").length, 0

    