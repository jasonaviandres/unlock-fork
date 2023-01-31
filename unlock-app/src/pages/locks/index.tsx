import React from 'react'
import type { NextPage } from 'next'
import BrowserOnly from '~/components/helpers/BrowserOnly'
import LocksListPage from '~/components/interface/locks/List'
import { AppLayout } from '~/components/interface/layouts/AppLayout'
import { Button } from '@unlock-protocol/ui'
import Link from 'next/link'
import { useAuth } from '~/contexts/AuthenticationContext'

const Locks: NextPage = () => {
  const { account } = useAuth()

  const Description = () => {
    return (
      <div className="flex flex-col gap-4 md:gap-0 md:justify-between md:flex-row">
        <span className="w-full max-w-lg text-base text-white/70">
          An Event is a smart contract you create, deploy, and own on MoonLab
        </span>
        {account && (
          <Link href="/locks/create">
            <Button
              className="bg-gray-600 hover:bg-white hover:text-black"
              size="large"
            >
              Create Event
            </Button>
          </Link>
        )}
      </div>
    )
  }
  return (
    <BrowserOnly>
      <AppLayout title="Events" description={<Description />}>
        <LocksListPage />
      </AppLayout>
    </BrowserOnly>
  )
}

export default Locks
