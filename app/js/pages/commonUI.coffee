forms = require 'mwater-forms'
siteTypes = require('mwater-common').siteTypes

# Creates type, name, desc, location questions for a site
# Model should will/should contain: 
# name: { value: <name> }
# desc: { value: <desc> }
# type: { value: <type> }
# location: { value: <location> }
#
# filterSiteTypes: list of site types to restrict to. Null for all
# isNew true if new site (can change site type)
exports.createBasicSiteQuestions = (model, ctx, filterSiteTypes, isNew) ->
  # When type changes, clear subtype
  model.on "change:type", =>
    model.unset("subtype")

  # Create context for forms
  formCtx = {
    displayMap: (location, setLocation) =>
      options = {}
      options.setLocation = setLocation
      if location?
        options.initialGeo = { type: 'Point', coordinates: [location.longitude, location.latitude] }
      ctx.pager.openPage require("./SiteMapPage"), options
  }

  # Create questions
  contents = []

  choices = []
  for siteType in siteTypes
    # Filter site types
    if filterSiteTypes and siteType.name not in filterSiteTypes
      continue

    choices.push { id: siteType.name, label: T(siteType.name)}

  if isNew
    contents.push new forms.DropdownQuestion
      T: T
      id: 'type'
      model: model
      prompt: T('Select site type')
      choices: choices
      required: true
  
  # Create subtype questions
  for siteType in siteTypes
    if siteType.subtypes.length == 0
      continue

    do (siteType) =>
      contents.push new forms.DropdownQuestion
        T: T
        id: 'subtype'
        model: model
        prompt: T('Select optional site subtype')
        choices: _.map(siteType.subtypes, (st) => { id: st, label: T(st) })
        conditional: () =>
          return model.get("type").value == siteType.name

  contents.push new forms.TextQuestion
    T: T
    id: 'name'
    model: model
    prompt: T('Enter optional name')

  contents.push new forms.TextQuestion
    T: T
    id: 'desc'
    model: model
    prompt: T('Enter optional description')

  contents.push new forms.LocationQuestion
    ctx: formCtx
    T: T
    id: 'location'
    model: model
    prompt: T('Enter site location')

  return contents

# Model will contain attributes in mwater-forms style
# e.g. { "Pump/lifting device": { value: "India MKII" } }
# e.g. { "Pump/lifting device": { alternate: "Dont Know" } }
# e.g. { "Pump/lifting device": { value: "Other", specify: { "Other": "some type" } } }
exports.createSiteAttributeQuestions = (siteType, model) ->
  contents = []

  subtype = siteType[1]

  # Handle water points
  if siteType[0] == "Water point"

    # No attributes if no subtype
    if not subtype
      return contents

    # Get lifting device options
    liftOptions = []

    if subtype in ["Protected dug well", "Borehole or tubewell", "Protected spring"]
      liftOptions.push("India MKII")
      liftOptions.push("India MKIII")
      liftOptions.push("Afridev")
      liftOptions.push("Maldev")
      liftOptions.push("Rope pump")

    if subtype == "Unprotected dug well"
      liftOptions.push("Rope and bucket")

    if subtype in ["Protected dug well", "Borehole or tubewell", "Protected spring"]
      liftOptions.push("Nira")
      liftOptions.push("EMAS pump")
      liftOptions.push("Tara")
      liftOptions.push("U2")
      liftOptions.push("U3")
      liftOptions.push("Poldaw")

    if subtype in ["Protected dug well", "Unprotected dug well", "Borehole or tubewell", "Protected spring", "Unprotected spring", "Rainwater", "Surface water"]
      liftOptions.push("Mono pump")
      liftOptions.push("Submersible pump")

    if subtype == "Surface water"
      liftOptions.push("Hydraulic ram")

    if subtype in ["Protected dug well", "Borehole or tubewell", "Protected spring"]
      liftOptions.push("Vergnet")
      liftOptions.push("Consallen")

    if liftOptions.length > 0
      choices = _.map(liftOptions, (opt) => { id: opt, label: T(opt) })
      choices.push { id: "Other", label: T("Other (please specify)"), specify: true }

      contents.push new forms.DropdownQuestion
        T: T
        id: "Pump/lifting device"
        model: model
        prompt: T("Pump/lifting device")
        choices: choices
        alternates: [ { id: "dontknow", label: T("Don't know") } ]

      poweredOptions = ["Manual", "Fuel", "Solar", "Wind", "Electrical grid"]
      contents.push new forms.DropdownQuestion
        T: T
        id: "Powered by"
        model: model
        prompt: T("Powered by")
        choices: _.map(poweredOptions, (opt) => { id: opt, label: T(opt) })
        alternates: [ { id: "dontknow", label: T("Don't know") } ]
        conditional: () =>
          model.get("Pump/lifting device") and model.get("Pump/lifting device").value

    if subtype in ["Protected dug well", "Unprotected dug well", "Borehole or tubewell"]
      drillingOptions = ["Manually drilled", "Mechanically drilled"]
      if subtype == "Borehole or tubewell"
        drillingOptions.push("Drilling rig")

      choices = _.map(drillingOptions, (opt) => { id: opt, label: T(opt) })
      choices.push { id: "Other", label: T("Other (please specify)"), specify: true }

      contents.push new forms.DropdownQuestion
        T: T
        id: "Drilling method"
        model: model
        prompt: T("Drilling method")
        choices: choices
        alternates: [ { id: "dontknow", label: T("Don't know") } ]

    supplyOptions = []
    if subtype in ["Piped into dwelling", "Piped into yard/plot", "Piped into public tap or basin"]
      supplyOptions.push("Gravity flow scheme")

    if subtype in ["Piped into dwelling", "Piped into yard/plot", "Piped into public tap or basin", "Bottled water", "Tanker truck", "Cart with small tank/drum"]
      supplyOptions.push("Protected dug well")
      supplyOptions.push("Borehole or tubewell")
      supplyOptions.push("Protected spring")
      supplyOptions.push("Rainwater")
      supplyOptions.push("Surface water - gravity flow scheme")
      supplyOptions.push("Surface water - pumped")
      supplyOptions.push("Surface water - earth/concrete dam")
      supplyOptions.push("Surface water - weir")

    if subtype in ["Protected dug well", "Unprotected dug well", "Borehole or tubewell", "Protected spring", "Unprotected spring", "Rainwater", "Surface water"]
      supplyOptions.push("Sand dam")
      supplyOptions.push("Infiltration gallery or riverbank filtration")

    if subtype in ["Piped into dwelling", "Piped into yard/plot", "Piped into public tap or basin", "Bottled water", "Tanker truck", "Cart with small tank/drum"]
      supplyOptions.push("Seawater (desalination)")

    if supplyOptions.length > 0
      choices = _.map(supplyOptions, (opt) => { id: opt, label: T(opt) })
      # TODO condition?
      choices.push { id: "Other", label: T("Other (please specify)"), specify: true }

      contents.push new forms.MulticheckQuestion
        T: T
        id: "Supply"
        model: model
        prompt: T("Supply")
        choices: choices
        alternates: [ { id: "dontknow", label: T("Don't know") } ] # TODO condition?

    treatmentOptions = ['Slow sand filter', 'Biosand filter', 'Rapid sand filter', 'Upflow sand filter', 'Membrane filter']

    if subtype in ["Piped into dwelling", "Piped into yard/plot", "Piped into public tap or basin", "Bottled water", "Tanker truck", "Cart with small tank/drum"]
      treatmentOptions.push("Coagulation with alum")
      treatmentOptions.push("Coagulation with polymer")
      treatmentOptions.push("Sedimentation")
      treatmentOptions.push("Pre-chlorination")
      treatmentOptions.push("Aeration")
      treatmentOptions.push("Desalination")

    treatmentOptions.push("Arsenic removal")
    treatmentOptions.push("Iron removal")
    treatmentOptions.push("Disinfection with chlorine")
    treatmentOptions.push("Disinfection with UV")
    treatmentOptions.push("Disinfection with ozone")
    treatmentOptions.push("Solar disinfection")

    choices = _.map(treatmentOptions, (opt) => { id: opt, label: T(opt) })

    contents.push new forms.MulticheckQuestion
      T: T
      id: "Treatment works"
      model: model
      prompt: T("Treatment works")
      choices: choices

  if siteType[0] == "Sanitation facility"
    # TODO flushes into

    if subtype in ["Flush/pour flush toilet", "Ventilated improved pit latrine", "Pit latrine with slab", "Composting toilet", "Pit latrine without slab", "Hanging latrine"]
      emptyingOptions = ["Manual emptying", "Dig new pit", "Mechanical pumping", "Vacuum tanker truck"]

      choices = _.map(emptyingOptions, (opt) => { id: opt, label: T(opt) })

      contents.push new forms.DropdownQuestion
        T: T
        id: "Pit emptying"
        model: model
        prompt: T("Pit emptying")
        choices: choices

    if subtype == "Flush/pour flush toilet"
      treatmentOptions = ["Biogas Generator", "Constructed Wetlands", "Waste Stabilisation Pond"]

      contents.push new forms.DropdownQuestion
        T: T
        id: "Treatment"
        model: model
        prompt: T("Treatment")
        choices: choices

  return contents
