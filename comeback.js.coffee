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

    makeid = ->
      text = ""
      possible = "ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789"
      i = 0

      while i < 5
        text += possible.charAt(Math.floor(Math.random() * possible.length))
        i++
      text

    Meteor.methods
      encode: (input_file, output_file, output_length)->
        job_id = Jobs.insert({status: "created"})
        file = "/tmp/#{makeid()}.txt"
        
        child_process.exec "ffmpeg -i #{input_file} 2>&1 | grep Duration", (error, stdout, stderr) ->        
          console.log "inspecting input file"
          inspect = stdout.split(",")
          tc = inspect[0].split(": ")[1]
          tc = tc.split(":")
          h = parseInt tc[0] * 60 * 60
          m = parseInt tc[1] * 60
          s = parseInt tc[2].split(".")[0]
          duration = h + m + s 
          Fiber ->
            Jobs.update({_id: job_id}, {$set: {status: 'inspecting', duration: duration, input_file: input_file, output_file: output_file, progress: 0}})        
          .run()
          
          child_process.exec "ffmpeg -y -i #{input_file} -t #{output_length} #{output_file}.mp4 2>&1 | tee #{file}", (error, stdout, stderr) ->
            fs.unwatchFile(file)
            Fiber ->
              if error
                Jobs.update({_id: job_id}, {$set: {status: 'error', progress: 100, log: stdout}})  
              else
                Jobs.update({_id: job_id}, {$set: {status: 'finished', progress: 100, log: stdout}})
            .run()

        fs.watchFile "#{file}", (curr, prev) ->
          child_process.exec("tail -n1 #{file}", (error, stdout, stderr) ->
            output = stdout.split(/\r\n|\r|\n/)
            output = output[output.length - 2]
            Fiber( ->
              job = Jobs.findOne({_id: job_id})
              
              if output
                t = output.match(/time=\d*\.\d*/)
                if t
                  duration = job.duration
                  time = t[0].split("=")[1] # time=12.12
                  progress = ((time / duration)*100)
                  progress = Math.round(progress)
                else
                  progress = 0
              
              if job
                Jobs.update({_id: job_id}, {$set: {status: 'encoding', progress: progress}})
            ).run()
          )
