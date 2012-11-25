Jobs = new Meteor.Collection("jobs")

if Meteor.isClient

  Template.encoding_job.job = ->
    Jobs.find({})

  Template.encoding_job.events "click input#create-job": ->
    input_file = $('#input_file').val()
    output_file = $('#output_file').val()
    output_length = parseInt $('#output_length').val()
    console.log "Submitting Encoding Job"  if typeof console isnt "undefined"
    Meteor.call("encode", input_file, output_file, output_length)

if Meteor.isServer
  Meteor.startup ->

    require = __meteor_bootstrap__.require
    child_process = require 'child_process'
    fs = require 'fs'
    kue = require('kue')
    jobs = kue.createQueue();    

    Meteor.methods
      encode: (input_file, output_file, output_length) ->
        job_id = Jobs.insert({status: "pending"})
        job = jobs.create 'video',
          job_id: job_id
          title: 'Encode Video'
          input_file: input_file
          output_file: output_file
          output_length: output_length
        .save( (err) ->
          Fiber ->
            Jobs.update({_id: job.data.job_id}, {$set: {queue_id: job.id }})        
          .run()
        )
        .on 'progress', (progress) ->
          console.log "progress #{progress}"
          if progress == 0
            status = "inspecting"
          else
            status = "encoding"
          Fiber ->
            Jobs.update({_id: job.data.job_id}, {$set: {status: status, duration: job.data.duration, progress: progress}})
          .run()
        
      jobs.on 'job complete', (id) ->
        kue.Job.get id, (err, job) -> 
          console.log "job done #{job.id}"
          Fiber ->
            Jobs.update({_id: job.data.job_id}, {$set: {status: 'finished', progress: 100 }})
          .run()
