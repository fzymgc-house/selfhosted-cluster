import * as wmill from 'npm:windmill-client@^1.158.2'

type Discord = {
  webhook_url: string
}

export async function main(
  module: string,
  plan_summary: string,
  plan_details: string,
  run_id: string
) {
  const resumeUrls = await wmill.getResumeUrls('admin')

  return {
    resume: resumeUrls['resume'],
    cancel: resumeUrls['cancel'],
    default_args: {},
    enums: {}
  }
}
